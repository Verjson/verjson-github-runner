#!/usr/bin/env python3
"""Build an auditable, strictly read-only GHCR retention inventory plan."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
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
POLICY = "ghcr-retention-v2"
MINIMUM_AGE_DAYS = 30
MAXIMUM_OBSERVATION_GAP_DAYS = 14
MAXIMUM_MANIFEST_BYTES = 10 * 1024 * 1024
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
SECRET_ENVIRONMENT_KEYS = {
    "ACTIONS_RUNTIME_TOKEN",
    "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
    "GH_TOKEN",
    "GITHUB_TOKEN",
}


class RetentionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Version:
    id: int
    digest: str
    created_at: datetime
    updated_at: datetime
    tags: tuple[str, ...]


@dataclass(frozen=True)
class Descriptor:
    media_type: str
    digest: str
    size: int


@dataclass(frozen=True)
class Manifest:
    raw: bytes
    value: dict[str, Any]


class CommandRunner:
    @staticmethod
    def run(command: list[str], *, allow_github_token: bool) -> bytes:
        environment = os.environ.copy()
        if not allow_github_token:
            for name in SECRET_ENVIRONMENT_KEYS:
                environment.pop(name, None)
        try:
            completed = subprocess.run(
                command,
                check=True,
                capture_output=True,
                timeout=60,
                env=environment,
            )
        except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            detail = getattr(error, "stderr", b"") or str(error)
            if isinstance(detail, bytes):
                detail = detail.decode("utf-8", errors="replace")
            raise RetentionError(f"external command failed: {command[0]}: {detail.strip()}") from error
        return completed.stdout


class GitHubApi:
    def package_versions(self) -> list[dict[str, Any]]:
        output = CommandRunner.run(
            [
                "gh",
                "api",
                "--paginate",
                "--slurp",
                f"/orgs/{OWNER}/packages/container/{PACKAGE}/versions?per_page=100",
            ],
            allow_github_token=True,
        )
        result = parse_json(output, "gh")
        if not isinstance(result, list):
            raise RetentionError("GitHub returned a non-list package inventory")
        pages = result if not result or isinstance(result[0], list) else [result]
        if not all(isinstance(page, list) for page in pages):
            raise RetentionError("GitHub returned an invalid paginated package inventory")
        return [item for page in pages for item in page]


class RegistryApi:
    def manifest(self, digest: str) -> bytes:
        if not DIGEST_RE.fullmatch(digest):
            raise RetentionError(f"invalid requested registry digest: {digest!r}")
        raw = CommandRunner.run(
            ["docker", "buildx", "imagetools", "inspect", "--raw", f"{IMAGE}@{digest}"],
            allow_github_token=False,
        )
        if not raw or len(raw) > MAXIMUM_MANIFEST_BYTES:
            raise RetentionError(f"registry manifest {digest} has an invalid byte length")
        actual = "sha256:" + hashlib.sha256(raw).hexdigest()
        if actual != digest:
            raise RetentionError(f"registry manifest digest mismatch for {digest}: received {actual}")
        value = parse_json(raw, "docker")
        if not isinstance(value, dict):
            raise RetentionError(f"registry returned a non-object manifest for {digest}")
        return raw


def parse_json(raw: bytes, command: str) -> Any:
    def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ValueError(f"duplicate JSON key: {key}")
            value[key] = item
        return value

    try:
        return json.loads(raw, object_pairs_hook=unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
        raise RetentionError(f"external command returned invalid JSON: {command}") from error


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


def format_time(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


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
        if not isinstance(version_id, int) or isinstance(version_id, bool) or version_id <= 0:
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


def parse_descriptor(
    value: Any, location: str, allowed_media_types: set[str] | None = None
) -> Descriptor:
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
    return Descriptor(media_type, digest, size)


def parse_manifest_evidence(
    digest: str, value: Any
) -> tuple[set[Descriptor], Descriptor | None]:
    if not isinstance(value, dict):
        raise RetentionError(f"manifest {digest} is not a JSON object")
    if value.get("schemaVersion") != 2:
        raise RetentionError(f"manifest {digest} has unsupported or missing schemaVersion")
    media_type = value.get("mediaType")
    if media_type not in SUPPORTED_MEDIA_TYPES:
        raise RetentionError(f"manifest {digest} has unsupported or missing mediaType: {media_type!r}")

    dependencies: set[Descriptor] = set()
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
            "updated_at": format_time(version.updated_at),
            "tags": version.tags,
        }
        for version in sorted(versions, key=lambda item: item.id)
    ]
    return sha256(inventory)


def inspect_manifests(api: RegistryApi, digests: Iterable[str]) -> dict[str, Manifest]:
    digest_list = sorted(digests)
    manifests: dict[str, Manifest] = {}
    with ThreadPoolExecutor(max_workers=min(8, len(digest_list))) as executor:
        futures = {executor.submit(api.manifest, digest): digest for digest in digest_list}
        for future in as_completed(futures):
            digest = futures[future]
            try:
                raw = future.result()
                if not isinstance(raw, bytes):
                    raise RetentionError(f"registry returned non-byte evidence for {digest}")
                actual = "sha256:" + hashlib.sha256(raw).hexdigest()
                if actual != digest:
                    raise RetentionError(f"registry manifest digest mismatch for {digest}: received {actual}")
                value = parse_json(raw, "docker")
                if not isinstance(value, dict):
                    raise RetentionError(f"registry returned a non-object manifest for {digest}")
                manifests[digest] = Manifest(raw, value)
            except Exception as error:
                for pending in futures:
                    pending.cancel()
                if isinstance(error, RetentionError):
                    raise
                raise RetentionError(f"registry inspection failed for {digest}: {error}") from error
    return manifests


def verified_prior_observations(
    prior_plan: dict[str, Any] | None, now: datetime
) -> tuple[dict[tuple[int, str], datetime], str | None, str]:
    if prior_plan is None:
        return {}, None, "missing_prior_evidence"
    try:
        prior_hash = verify_plan(prior_plan)
        generated_at = parse_time(prior_plan["generated_at"])
        if generated_at >= now:
            raise RetentionError("prior observation is not older than the current plan")
        if now - generated_at > timedelta(days=MAXIMUM_OBSERVATION_GAP_DAYS):
            raise RetentionError("prior observation exceeds the continuity window")
        chain = prior_plan["observation_chain"]
        if not isinstance(chain, dict):
            raise RetentionError("prior observation chain metadata is invalid")
        chain_status = chain.get("status")
        previous_hash = chain.get("previous_plan_sha256")
        if chain_status == "continued":
            if not isinstance(previous_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", previous_hash):
                raise RetentionError("prior observation chain has no valid predecessor")
        elif chain_status in {
            "missing_prior_evidence",
            "untrusted_or_discontinuous_prior_evidence",
        }:
            if previous_hash is not None:
                raise RetentionError("reset prior observation unexpectedly names a predecessor")
        else:
            raise RetentionError("prior observation chain status is invalid")
        raw_observations = prior_plan["untagged_classifications"]
        if not isinstance(raw_observations, list):
            raise RetentionError("prior observation list is invalid")
        observations: dict[tuple[int, str], datetime] = {}
        ids: set[int] = set()
        digests: set[str] = set()
        for raw in raw_observations:
            if not isinstance(raw, dict):
                raise RetentionError("prior observation entry is invalid")
            version_id = raw.get("id")
            digest = raw.get("digest")
            first_observed = parse_time(raw.get("first_observed_untagged"))
            if (
                not isinstance(version_id, int)
                or isinstance(version_id, bool)
                or version_id <= 0
                or not isinstance(digest, str)
                or not DIGEST_RE.fullmatch(digest)
                or first_observed > generated_at
                or raw.get("classification")
                not in {
                    "referenced_oci_dependency",
                    "retention_candidate",
                    "unreachable_but_inside_age_floor",
                }
            ):
                raise RetentionError("prior observation entry has invalid identity or time")
            key = (version_id, digest)
            if version_id in ids or digest in digests:
                raise RetentionError("prior observation contains duplicate identities")
            ids.add(version_id)
            digests.add(digest)
            observations[key] = first_observed
        counts = prior_plan.get("counts")
        if not isinstance(counts, dict) or counts.get("untagged") != len(observations):
            raise RetentionError("prior observation count does not match its entries")
        return observations, prior_hash, "continued"
    except (KeyError, TypeError, RetentionError):
        return {}, None, "untrusted_or_discontinuous_prior_evidence"


def build_plan(
    raw_versions: Iterable[dict[str, Any]],
    api: RegistryApi,
    now: datetime,
    prior_plan: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if now.tzinfo is None:
        raise RetentionError("plan clock must be timezone-aware")
    now = now.astimezone(timezone.utc)
    versions = parse_versions(raw_versions)
    for version in versions:
        if version.created_at > now or version.updated_at > now or version.updated_at < version.created_at:
            raise RetentionError(f"package version {version.id} has impossible timestamps")
    by_digest = {version.digest: version for version in versions}
    prior_observations, prior_hash, continuity = verified_prior_observations(prior_plan, now)

    dependencies: dict[str, set[str]] = {digest: set() for digest in by_digest}
    parents: dict[str, set[str]] = {digest: set() for digest in by_digest}
    subjects: dict[str, str] = {}
    manifests = inspect_manifests(api, by_digest)
    for digest in sorted(by_digest):
        referenced, subject = parse_manifest_evidence(digest, manifests[digest].value)
        missing = sorted(item.digest for item in referenced if item.digest not in by_digest)
        if missing:
            raise RetentionError(f"manifest {digest} references a version absent from inventory: {missing[0]}")
        if any(item.digest == digest for item in referenced):
            raise RetentionError(f"manifest {digest} references itself")
        for child in referenced:
            if child.size != len(manifests[child.digest].raw):
                raise RetentionError(f"manifest {digest} descriptor size does not match {child.digest}")
            if child.media_type != manifests[child.digest].value.get("mediaType"):
                raise RetentionError(f"manifest {digest} descriptor mediaType does not match {child.digest}")
            dependencies[digest].add(child.digest)
            parents[child.digest].add(digest)
        if subject is not None:
            if subject.digest not in by_digest:
                raise RetentionError(f"manifest {digest} subject is absent from inventory: {subject.digest}")
            if subject.digest == digest:
                raise RetentionError(f"manifest {digest} names itself as subject")
            if subject.size != len(manifests[subject.digest].raw):
                raise RetentionError(f"manifest {digest} subject size does not match {subject.digest}")
            if subject.media_type != manifests[subject.digest].value.get("mediaType"):
                raise RetentionError(f"manifest {digest} subject mediaType does not match {subject.digest}")
            subjects[digest] = subject.digest

    for referrer, subject in subjects.items():
        dependencies[subject].add(referrer)
        dependencies[subject].update(parents[referrer])

    conventional_tagged = {
        version.digest
        for version in versions
        if any(not SYNTHETIC_ATTESTATION_TAG_RE.fullmatch(tag) for tag in version.tags)
    }
    tagged = {version.digest for version in versions if version.tags}
    reachable: set[str] = set()
    pending = list(tagged)
    while pending:
        digest = pending.pop()
        if digest in reachable:
            continue
        reachable.add(digest)
        pending.extend(dependencies[digest] - reachable)

    untagged = [version for version in versions if not version.tags]
    first_observed = {
        version.digest: max(
            prior_observations.get((version.id, version.digest), now),
            version.created_at,
        )
        for version in untagged
    }
    cutoff = now - timedelta(days=MINIMUM_AGE_DAYS)
    candidates = sorted(
        (
            version
            for version in untagged
            if first_observed[version.digest] < cutoff and version.digest not in reachable
        ),
        key=lambda version: (first_observed[version.digest], version.id),
    )
    candidate_digests = {version.digest for version in candidates}
    classifications = []
    for version in sorted(untagged, key=lambda item: item.id):
        if version.digest in reachable:
            classification = "referenced_oci_dependency"
        elif version.digest in candidate_digests:
            classification = "retention_candidate"
        else:
            classification = "unreachable_but_inside_age_floor"
        classifications.append(
            {
                "id": version.id,
                "digest": version.digest,
                "first_observed_untagged": format_time(first_observed[version.digest]),
                "classification": classification,
            }
        )
    plan: dict[str, Any] = {
        "schema_version": 2,
        "policy": POLICY,
        "owner": OWNER,
        "package": PACKAGE,
        "image": IMAGE,
        "generated_at": format_time(now),
        "minimum_age_days": MINIMUM_AGE_DAYS,
        "maximum_observation_gap_days": MAXIMUM_OBSERVATION_GAP_DAYS,
        "inventory_fingerprint": inventory_fingerprint(versions),
        "observation_chain": {
            "status": continuity,
            "previous_plan_sha256": prior_hash,
        },
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
                "created_at": format_time(version.created_at),
                "updated_at": format_time(version.updated_at),
                "age_reference": format_time(first_observed[version.digest]),
                "reason": "observed untagged across an uninterrupted plan chain outside the age floor and unreachable from tagged OCI roots",
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
        plan.get("schema_version") != 2
        or plan.get("policy") != POLICY
        or plan.get("owner") != OWNER
        or plan.get("package") != PACKAGE
        or plan.get("image") != IMAGE
        or plan.get("minimum_age_days") != MINIMUM_AGE_DAYS
        or plan.get("maximum_observation_gap_days") != MAXIMUM_OBSERVATION_GAP_DAYS
        or plan.get("pruning_authorized") is not False
    ):
        raise RetentionError("retention plan does not match the governing policy")
    return actual


def read_json(path: Path) -> Any:
    try:
        return parse_json(path.read_bytes(), str(path))
    except (OSError, RetentionError) as error:
        raise RetentionError(f"cannot read valid JSON from {path}") from error


def read_optional_json(path: Path | None) -> dict[str, Any] | None:
    if path is None or not path.is_file():
        return None
    try:
        value = parse_json(path.read_bytes(), str(path))
    except (OSError, RetentionError):
        return {}
    return value if isinstance(value, dict) else {}


def write_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(canonical_json(value))
    temporary.replace(path)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)
    inventory = subcommands.add_parser("inventory")
    inventory.add_argument("--output", type=Path, required=True)
    plan = subcommands.add_parser("plan")
    plan.add_argument("--inventory", type=Path, required=True)
    plan.add_argument("--prior-plan", type=Path)
    plan.add_argument("--output", type=Path, required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "inventory":
            write_json(args.output, GitHubApi().package_versions())
            return 0
        inventory = read_json(args.inventory)
        if not isinstance(inventory, list):
            raise RetentionError("inventory input is not a list")
        plan = build_plan(
            inventory,
            RegistryApi(),
            datetime.now(timezone.utc),
            read_optional_json(args.prior_plan),
        )
        write_json(args.output, plan)
        print(json.dumps({"plan_sha256": plan["plan_sha256"], **plan["counts"]}, sort_keys=True))
    except (OSError, RetentionError) as error:
        print(f"ghcr retention: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
