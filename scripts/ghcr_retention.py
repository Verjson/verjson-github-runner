#!/usr/bin/env python3
"""Build and, only under explicit policy gates, apply a GHCR retention plan."""

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
POLICY = "ghcr-retention-v1"
MINIMUM_AGE_DAYS = 30
MAX_DELETE_BATCH = 50
DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
SYNTHETIC_ATTESTATION_TAG_RE = re.compile(r"^sha256-[0-9a-f]{64}$")


class RetentionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Version:
    id: int
    digest: str
    created_at: datetime
    updated_at: str
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

    def delete_version(self, version_id: int) -> None:
        self._command(
            [
                "gh",
                "api",
                "--method",
                "DELETE",
                f"/orgs/{OWNER}/packages/container/{PACKAGE}/versions/{version_id}",
            ]
        )

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
                updated_at=updated_at,
                tags=tuple(sorted(set(tags_raw))),
            )
        )
    if not versions:
        raise RetentionError("GitHub package inventory is empty")
    if len(versions) > 5000:
        raise RetentionError("package inventory exceeds the audited 5,000-version bound")
    return versions


def descriptor_digests(value: Any) -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        digest = value.get("digest")
        if isinstance(digest, str) and DIGEST_RE.fullmatch(digest):
            found.add(digest)
        for child in value.values():
            found.update(descriptor_digests(child))
    elif isinstance(value, list):
        for child in value:
            found.update(descriptor_digests(child))
    return found


def parse_protected_digests(raw: str) -> set[str]:
    if not raw.strip():
        return set()
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        value = [line.strip() for line in raw.splitlines() if line.strip()]
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise RetentionError("protected digests must be a JSON array or one digest per line")
    protected = set(value)
    invalid = sorted(digest for digest in protected if not DIGEST_RE.fullmatch(digest))
    if invalid:
        raise RetentionError(f"invalid protected digest: {invalid[0]}")
    return protected


def inventory_fingerprint(versions: Iterable[Version]) -> str:
    inventory = [
        {"id": version.id, "digest": version.digest, "updated_at": version.updated_at, "tags": version.tags}
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


def build_plan(
    api: ExternalApi,
    protected: set[str],
    now: datetime,
) -> dict[str, Any]:
    if now.tzinfo is None:
        raise RetentionError("plan clock must be timezone-aware")
    versions = parse_versions(api.package_versions())
    by_digest = {version.digest: version for version in versions}
    missing_protected = sorted(protected - by_digest.keys())
    if missing_protected:
        raise RetentionError(f"protected deployment digest is absent from GHCR: {missing_protected[0]}")

    dependencies: dict[str, set[str]] = {digest: set() for digest in by_digest}
    parents: dict[str, set[str]] = {digest: set() for digest in by_digest}
    subjects: dict[str, str] = {}
    manifests = inspect_manifests(api, by_digest)
    for digest in sorted(by_digest):
        manifest = manifests[digest]
        subject = manifest.get("subject")
        if isinstance(subject, dict):
            subject_digest = subject.get("digest")
            if isinstance(subject_digest, str) and subject_digest in by_digest:
                subjects[digest] = subject_digest
        content = {key: value for key, value in manifest.items() if key != "subject"}
        referenced = descriptor_digests(content) & by_digest.keys()
        referenced.discard(digest)
        dependencies[digest].update(referenced)
        for child in referenced:
            parents[child].add(digest)

    for referrer, subject in subjects.items():
        dependencies[subject].add(referrer)
        dependencies[subject].update(parents[referrer])

    conventional_tagged = {
        version.digest
        for version in versions
        if any(not SYNTHETIC_ATTESTATION_TAG_RE.fullmatch(tag) for tag in version.tags)
    }
    tagged = {version.digest for version in versions if version.tags}
    roots = tagged | protected
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
            if not version.tags and version.created_at < cutoff and version.digest not in reachable
        ),
        key=lambda version: (version.created_at, version.id),
    )
    delete_batch = candidates[:MAX_DELETE_BATCH]
    candidate_digests = {version.digest for version in candidates}
    untagged = [version for version in versions if not version.tags]
    classifications = []
    for version in sorted(untagged, key=lambda item: item.id):
        if version.digest in protected:
            classification = "deployment_or_rollback_root"
        elif version.digest in reachable:
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
        "max_delete_batch": MAX_DELETE_BATCH,
        "inventory_fingerprint": inventory_fingerprint(versions),
        "protected_digests": sorted(protected),
        "protected_digests_fingerprint": sha256(sorted(protected)),
        "deployment_inventory_supplied": bool(protected),
        "eligible_for_apply": bool(protected) and bool(delete_batch),
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
                version.digest in reachable and version.digest not in protected for version in untagged
            ),
            "protected_untagged_deployment_or_rollback_roots": sum(
                version.digest in protected for version in untagged
            ),
            "unreachable_untagged": sum(version.digest not in reachable for version in untagged),
            "unreachable_inside_age_floor": sum(
                version.digest not in reachable and version.digest not in candidate_digests
                for version in untagged
            ),
            "candidates": len(candidates),
            "delete_batch": len(delete_batch),
            "deferred_candidates": max(0, len(candidates) - len(delete_batch)),
        },
        "untagged_classifications": classifications,
        "delete_batch": [
            {
                "id": version.id,
                "digest": version.digest,
                "created_at": version.created_at.isoformat().replace("+00:00", "Z"),
                "reason": "untagged, older than policy floor, and unreachable from protected roots",
            }
            for version in delete_batch
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
        or plan.get("max_delete_batch") != MAX_DELETE_BATCH
    ):
        raise RetentionError("retention plan does not match the governing policy")
    return actual


def write_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(canonical_json(value))
    temporary.replace(path)


def apply_plan(
    api: ExternalApi,
    plan: dict[str, Any],
    protected: set[str],
    confirm_sha256: str,
    authorization: str,
    receipt_path: Path,
    now: datetime,
) -> dict[str, Any]:
    plan_hash = verify_plan(plan)
    if authorization != POLICY:
        raise RetentionError("manual deletion policy is not enabled")
    if confirm_sha256 != plan_hash:
        raise RetentionError("manual confirmation does not match the reviewed plan")
    if not plan.get("deployment_inventory_supplied") or not plan.get("eligible_for_apply"):
        raise RetentionError("plan is ineligible: protected deployment inventory and candidates are required")
    if plan.get("protected_digests") != sorted(protected):
        raise RetentionError("protected deployment inventory changed after the plan was created")
    batch = plan.get("delete_batch")
    if not isinstance(batch, list) or not batch or len(batch) > MAX_DELETE_BATCH:
        raise RetentionError("delete batch is empty or exceeds the policy bound")

    replacement = build_plan(api, protected, now)
    if replacement["inventory_fingerprint"] != plan.get("inventory_fingerprint"):
        raise RetentionError("GHCR inventory changed after the plan was created")
    replacement_targets = [(item["id"], item["digest"]) for item in replacement["delete_batch"]]
    planned_targets = [(item.get("id"), item.get("digest")) for item in batch if isinstance(item, dict)]
    if replacement_targets != planned_targets:
        raise RetentionError("retention decision changed after the plan was created")

    receipt: dict[str, Any] = {
        "schema_version": 1,
        "policy": POLICY,
        "plan_sha256": plan_hash,
        "started_at": now.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "deleted": [],
        "status": "in_progress",
    }
    write_json(receipt_path, receipt)
    for target in batch:
        api.delete_version(target["id"])
        receipt["deleted"].append({"id": target["id"], "digest": target["digest"]})
        write_json(receipt_path, receipt)
    receipt["status"] = "complete"
    write_json(receipt_path, receipt)
    return receipt


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)
    plan = subcommands.add_parser("plan")
    plan.add_argument("--output", type=Path, required=True)
    apply = subcommands.add_parser("apply")
    apply.add_argument("--plan", type=Path, required=True)
    apply.add_argument("--confirm-plan-sha256", required=True)
    apply.add_argument("--authorization", required=True)
    apply.add_argument("--receipt-output", type=Path, required=True)
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    api = ExternalApi()
    try:
        protected = parse_protected_digests(os.environ.get("GHCR_PROTECTED_DIGESTS", ""))
        now = datetime.now(timezone.utc)
        if args.command == "plan":
            plan = build_plan(api, protected, now)
            write_json(args.output, plan)
            print(json.dumps({"plan_sha256": plan["plan_sha256"], **plan["counts"]}, sort_keys=True))
        else:
            plan = json.loads(args.plan.read_text())
            receipt = apply_plan(
                api,
                plan,
                protected,
                args.confirm_plan_sha256,
                args.authorization,
                args.receipt_output,
                now,
            )
            print(json.dumps(receipt, sort_keys=True))
    except (OSError, json.JSONDecodeError, RetentionError) as error:
        print(f"ghcr retention: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
