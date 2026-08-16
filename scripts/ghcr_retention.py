#!/usr/bin/env python3
"""Build an auditable, strictly read-only GHCR retention inventory plan."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable


OWNER = "Verjson"
PACKAGE = "gha-runner"
IMAGE = "ghcr.io/verjson/gha-runner"
POLICY = "ghcr-retention-v1"
MINIMUM_AGE_DAYS = 30
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
SYNTHETIC_ATTESTATION_TAG_RE = re.compile(r"^sha256-[0-9a-f]{64}$")
INDEX_MEDIA_TYPES = {
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
}
MANIFEST_MEDIA_TYPES = {
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
}
ARTIFACT_MEDIA_TYPE = "application/vnd.oci.artifact.manifest.v1+json"
SUPPORTED_MEDIA_TYPES = INDEX_MEDIA_TYPES | MANIFEST_MEDIA_TYPES | {ARTIFACT_MEDIA_TYPE}


class RetentionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Version:
    id: int
    digest: str
    created_at: datetime
    updated_at: datetime
    tags: tuple[str, ...]


class ExternalApi:
    def package_versions(self) -> list[dict[str, Any]]:
        result = self._json_command(
            [
                "gh",
                "api",
                "--paginate",
                "--slurp",
                f"/orgs/{OWNER}/packages/container/{PACKAGE}/versions?per_page=100",
            ]
        )
        if not isinstance(result, list):
            raise RetentionError("GitHub returned a non-list package inventory")
        pages = result if not result or isinstance(result[0], list) else [result]
        return [item for page in pages for item in page]

    def manifest(self, digest: str) -> dict[str, Any]:
        result = self._json_command(
            ["docker", "buildx", "imagetools", "inspect", "--raw", f"{IMAGE}@{digest}"]
        )
        if not isinstance(result, dict):
            raise RetentionError(f"registry returned a non-object manifest for {digest}")
        return result

    @staticmethod
    def _command(command: list[str]) -> str:
        try:
            completed = subprocess.run(
                command,
                check=True,
                capture_output=True,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            detail = getattr(error, "stderr", "") or str(error)
            raise RetentionError(f"external command failed: {command[0]}: {detail.strip()}") from error
        return completed.stdout

    @classmethod
    def _json_command(cls, command: list[str]) -> Any:
        output = cls._command(command)
        try:
            return json.loads(output)
        except json.JSONDecodeError as error:
            raise RetentionError(f"external command returned invalid JSON: {command[0]}") from error


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def parse_time(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError) as error:
        raise RetentionError(f"invalid package timestamp: {value!r}") from error
    if parsed.tzinfo is None:
        raise RetentionError(f"package timestamp has no timezone: {value!r}")
    return parsed.astimezone(timezone.utc)


def parse_versions(raw_versions: Iterable[dict[str, Any]]) -> list[Version]:
    versions: list[Version] = []
    ids: set[int] = set()
    digests: set[str] = set()
    for raw in raw_versions:
        try:
            version_id = raw["id"]
            digest = raw["name"]
            created_at_raw = raw["created_at"]
            updated_at = raw["updated_at"]
            tags_raw = raw["metadata"]["container"]["tags"]
        except (KeyError, TypeError) as error:
            raise RetentionError("GitHub package inventory omitted a required field") from error
        if not isinstance(version_id, int) or version_id <= 0:
            raise RetentionError(f"invalid package version id: {version_id!r}")
        if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
            raise RetentionError(f"invalid package digest: {digest!r}")
        if not isinstance(updated_at, str) or not isinstance(tags_raw, list) or not all(
            isinstance(tag, str) and tag for tag in tags_raw
        ):
            raise RetentionError(f"invalid metadata for package version {version_id}")
        if version_id in ids or digest in digests:
            raise RetentionError("GitHub package inventory contains duplicate ids or digests")
        ids.add(version_id)
        digests.add(digest)
        versions.append(
            Version(
                id=version_id,
                digest=digest,
                created_at=parse_time(created_at_raw),
                updated_at=parse_time(updated_at),
                tags=tuple(sorted(set(tags_raw))),
            )
        )
    if not versions:
        raise RetentionError("GitHub package inventory is empty")
    if len(versions) > 5000:
        raise RetentionError("package inventory exceeds the audited 5,000-version bound")
    return versions


def parse_descriptor(value: Any, location: str, allowed_media_types: set[str] | None = None) -> str:
    if not isinstance(value, dict):
        raise RetentionError(f"{location} is not an OCI descriptor")
    media_type = value.get("mediaType")
    digest = value.get("digest")
    size = value.get("size")
    if not isinstance(media_type, str) or not media_type:
        raise RetentionError(f"{location} descriptor has no mediaType")
    if allowed_media_types is not None and media_type not in allowed_media_types:
        raise RetentionError(f"{location} descriptor has unsupported mediaType: {media_type}")
    if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
        raise RetentionError(f"{location} descriptor has an invalid digest")
    if not isinstance(size, int) or isinstance(size, bool) or size < 0:
        raise RetentionError(f"{location} descriptor has an invalid size")
    annotations = value.get("annotations")
    if annotations is not None and (
        not isinstance(annotations, dict)
        or not all(isinstance(key, str) and isinstance(item, str) for key, item in annotations.items())
    ):
        raise RetentionError(f"{location} descriptor has invalid annotations")
    return digest


def parse_manifest_evidence(digest: str, value: Any) -> tuple[set[str], str | None]:
    if not isinstance(value, dict):
        raise RetentionError(f"manifest {digest} is not a JSON object")
    if value.get("schemaVersion") != 2:
        raise RetentionError(f"manifest {digest} has unsupported or missing schemaVersion")
    media_type = value.get("mediaType")
    if media_type not in SUPPORTED_MEDIA_TYPES:
        raise RetentionError(f"manifest {digest} has unsupported or missing mediaType: {media_type!r}")

    dependencies: set[str] = set()
    if media_type in INDEX_MEDIA_TYPES:
        descriptors = value.get("manifests")
        if not isinstance(descriptors, list) or not descriptors:
            raise RetentionError(f"index {digest} has no manifest descriptors")
        for index, descriptor in enumerate(descriptors):
            dependencies.add(
                parse_descriptor(descriptor, f"manifest {digest} manifests[{index}]", SUPPORTED_MEDIA_TYPES)
            )
    elif media_type in MANIFEST_MEDIA_TYPES:
        parse_descriptor(value.get("config"), f"manifest {digest} config")
        layers = value.get("layers")
        if not isinstance(layers, list):
            raise RetentionError(f"manifest {digest} layers is not a list")
        for index, descriptor in enumerate(layers):
            parse_descriptor(descriptor, f"manifest {digest} layers[{index}]")
    else:
        artifact_type = value.get("artifactType")
        if not isinstance(artifact_type, str) or not artifact_type:
            raise RetentionError(f"artifact manifest {digest} has no artifactType")
        blobs = value.get("blobs")
        if not isinstance(blobs, list):
            raise RetentionError(f"artifact manifest {digest} blobs is not a list")
        for index, descriptor in enumerate(blobs):
            parse_descriptor(descriptor, f"manifest {digest} blobs[{index}]")

    subject_value = value.get("subject")
    subject = None
    if subject_value is not None:
        subject = parse_descriptor(subject_value, f"manifest {digest} subject", SUPPORTED_MEDIA_TYPES)
    return dependencies, subject


def inventory_fingerprint(versions: Iterable[Version]) -> str:
    inventory = [
        {
            "id": version.id,
            "digest": version.digest,
            "updated_at": version.updated_at.isoformat().replace("+00:00", "Z"),
            "tags": version.tags,
        }
        for version in sorted(versions, key=lambda item: item.id)
    ]
    return sha256(inventory)


def inspect_manifests(api: ExternalApi, digests: Iterable[str]) -> dict[str, dict[str, Any]]:
    digest_list = sorted(digests)
    manifests: dict[str, dict[str, Any]] = {}
    with ThreadPoolExecutor(max_workers=min(8, len(digest_list))) as executor:
        futures = {executor.submit(api.manifest, digest): digest for digest in digest_list}
        for future in as_completed(futures):
            digest = futures[future]
            try:
                manifests[digest] = future.result()
            except Exception as error:
                for pending in futures:
                    pending.cancel()
                if isinstance(error, RetentionError):
                    raise
                raise RetentionError(f"registry inspection failed for {digest}: {error}") from error
    return manifests


def build_plan(api: ExternalApi, now: datetime) -> dict[str, Any]:
    if now.tzinfo is None:
        raise RetentionError("plan clock must be timezone-aware")
    versions = parse_versions(api.package_versions())
    by_digest = {version.digest: version for version in versions}

    dependencies: dict[str, set[str]] = {digest: set() for digest in by_digest}
    parents: dict[str, set[str]] = {digest: set() for digest in by_digest}
    subjects: dict[str, str] = {}
    manifests = inspect_manifests(api, by_digest)
    for digest in sorted(by_digest):
        referenced, subject = parse_manifest_evidence(digest, manifests[digest])
        missing = sorted(referenced - by_digest.keys())
        if missing:
            raise RetentionError(f"manifest {digest} references a version absent from inventory: {missing[0]}")
        if digest in referenced:
            raise RetentionError(f"manifest {digest} references itself")
        dependencies[digest].update(referenced)
        for child in referenced:
            parents[child].add(digest)
        if subject is not None:
            if subject not in by_digest:
                raise RetentionError(f"manifest {digest} subject is absent from inventory: {subject}")
            if subject == digest:
                raise RetentionError(f"manifest {digest} names itself as subject")
            subjects[digest] = subject

    for referrer, subject in subjects.items():
        dependencies[subject].add(referrer)
        dependencies[subject].update(parents[referrer])

    conventional_tagged = {
        version.digest
        for version in versions
        if any(not SYNTHETIC_ATTESTATION_TAG_RE.fullmatch(tag) for tag in version.tags)
    }
    tagged = {version.digest for version in versions if version.tags}
    roots = tagged
    reachable: set[str] = set()
    pending = list(roots)
    while pending:
        digest = pending.pop()
        if digest in reachable:
            continue
        reachable.add(digest)
        pending.extend(dependencies[digest] - reachable)

    cutoff = now.astimezone(timezone.utc) - timedelta(days=MINIMUM_AGE_DAYS)
    candidates = sorted(
        (
            version
            for version in versions
            if not version.tags
            and max(version.created_at, version.updated_at) < cutoff
            and version.digest not in reachable
        ),
        key=lambda version: (max(version.created_at, version.updated_at), version.id),
    )
    candidate_digests = {version.digest for version in candidates}
    untagged = [version for version in versions if not version.tags]
    classifications = []
    for version in sorted(untagged, key=lambda item: item.id):
        if version.digest in reachable:
            classification = "referenced_oci_dependency"
        elif version.digest in candidate_digests:
            classification = "retention_candidate"
        else:
            classification = "unreachable_but_inside_age_floor"
        classifications.append(
            {"id": version.id, "digest": version.digest, "classification": classification}
        )
    plan: dict[str, Any] = {
        "schema_version": 1,
        "policy": POLICY,
        "owner": OWNER,
        "package": PACKAGE,
        "image": IMAGE,
        "generated_at": now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "minimum_age_days": MINIMUM_AGE_DAYS,
        "inventory_fingerprint": inventory_fingerprint(versions),
        "pruning_authorized": False,
        "authorization_blockers": [
            "explicit pruning authorization",
            "protected reviewer environment with verified governing policy",
            "operator-supplied identity of a previously reviewed plan",
            "strict durable evidence before and after every package mutation",
            "fresh completeness-verifiable deployment and rollback receipt",
        ],
        "counts": {
            "versions": len(versions),
            "tagged": sum(bool(version.tags) for version in versions),
            "untagged": len(untagged),
            "conventional_tagged_roots": len(conventional_tagged),
            "synthetic_attestation_tagged": sum(
                bool(version.tags)
                and all(SYNTHETIC_ATTESTATION_TAG_RE.fullmatch(tag) for tag in version.tags)
                for version in versions
            ),
            "reachable": len(reachable),
            "reachable_untagged_dependencies": sum(
                version.digest in reachable for version in untagged
            ),
            "unreachable_untagged": sum(version.digest not in reachable for version in untagged),
            "unreachable_inside_age_floor": sum(
                version.digest not in reachable and version.digest not in candidate_digests
                for version in untagged
            ),
            "candidates": len(candidates),
        },
        "untagged_classifications": classifications,
        "policy_candidates": [
            {
                "id": version.id,
                "digest": version.digest,
                "created_at": version.created_at.isoformat().replace("+00:00", "Z"),
                "updated_at": version.updated_at.isoformat().replace("+00:00", "Z"),
                "age_reference": max(version.created_at, version.updated_at)
                .isoformat()
                .replace("+00:00", "Z"),
                "reason": "untagged, outside the age floor, and unreachable from tagged OCI roots",
            }
            for version in candidates
        ],
    }
    plan["plan_sha256"] = sha256(plan)
    return plan


def verify_plan(plan: dict[str, Any]) -> str:
    expected = plan.get("plan_sha256")
    unsigned = dict(plan)
    unsigned.pop("plan_sha256", None)
    actual = sha256(unsigned)
    if not isinstance(expected, str) or expected != actual:
        raise RetentionError("retention plan hash does not match its contents")
    if (
        plan.get("schema_version") != 1
        or plan.get("policy") != POLICY
        or plan.get("owner") != OWNER
        or plan.get("package") != PACKAGE
        or plan.get("image") != IMAGE
        or plan.get("minimum_age_days") != MINIMUM_AGE_DAYS
        or plan.get("pruning_authorized") is not False
    ):
        raise RetentionError("retention plan does not match the governing policy")
    return actual


def write_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(canonical_json(value))
    temporary.replace(path)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)
    plan = subcommands.add_parser("plan")
    plan.add_argument("--output", type=Path, required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    api = ExternalApi()
    try:
        now = datetime.now(timezone.utc)
        plan = build_plan(api, now)
        write_json(args.output, plan)
        print(json.dumps({"plan_sha256": plan["plan_sha256"], **plan["counts"]}, sort_keys=True))
    except (OSError, json.JSONDecodeError, RetentionError) as error:
        print(f"ghcr retention: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
