#!/usr/bin/env python3

import importlib.util
import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ghcr_retention", ROOT / "scripts/ghcr_retention.py")
retention = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = retention
SPEC.loader.exec_module(retention)


def digest(character):
    return "sha256:" + character * 64


def descriptor(name, media_type="application/vnd.oci.image.manifest.v1+json"):
    return {"mediaType": media_type, "digest": name, "size": 1}


def image_manifest(subject=None):
    manifest = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": descriptor(digest("0"), "application/vnd.oci.image.config.v1+json"),
        "layers": [],
    }
    if subject is not None:
        manifest["subject"] = descriptor(subject, "application/vnd.oci.image.index.v1+json")
    return manifest


def image_index(*children):
    return {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.index.v1+json",
        "manifests": [descriptor(child) for child in children],
    }


def raw_version(version_id, name, created, tags=(), updated=None):
    return {
        "id": version_id,
        "name": name,
        "created_at": created,
        "updated_at": updated or created,
        "metadata": {"container": {"tags": list(tags)}},
    }


class FakeApi:
    def __init__(self, versions, manifests):
        self.versions = versions
        self.manifests = manifests

    def package_versions(self):
        return self.versions

    def manifest(self, name):
        value = self.manifests[name]
        if isinstance(value, Exception):
            raise value
        return value


class RetentionPlanTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 8, 16, tzinfo=timezone.utc)
        self.old = "2026-06-01T00:00:00Z"
        self.young = "2026-08-10T00:00:00Z"

    def test_preserves_tagged_graph_and_subject_linked_provenance(self):
        root = digest("a")
        platform = digest("b")
        attestation = digest("c")
        attestation_index = digest("d")
        old_orphan = digest("1")
        young_orphan = digest("2")
        versions = [
            raw_version(1, root, self.old, ["base-commit"]),
            raw_version(2, platform, self.old),
            raw_version(3, attestation, self.old),
            raw_version(4, attestation_index, self.old, ["sha256-" + "a" * 64]),
            raw_version(5, old_orphan, self.old),
            raw_version(6, young_orphan, self.young),
        ]
        manifests = {
            root: image_index(platform),
            platform: image_manifest(),
            attestation: image_manifest(subject=root),
            attestation_index: image_index(attestation),
            old_orphan: image_manifest(),
            young_orphan: image_manifest(),
        }

        plan = retention.build_plan(FakeApi(versions, manifests), self.now)

        self.assertEqual([old_orphan], [item["digest"] for item in plan["policy_candidates"]])
        self.assertEqual(4, plan["counts"]["reachable"])
        self.assertEqual(2, plan["counts"]["reachable_untagged_dependencies"])
        self.assertEqual(1, plan["counts"]["synthetic_attestation_tagged"])
        self.assertFalse(plan["pruning_authorized"])
        self.assertEqual(plan["plan_sha256"], retention.verify_plan(plan))

    def test_synthetic_attestation_tag_does_not_make_its_subject_a_release_root(self):
        subject = digest("a")
        referrer = digest("b")
        wrapper = digest("c")
        versions = [
            raw_version(1, subject, self.old),
            raw_version(2, referrer, self.old),
            raw_version(3, wrapper, self.old, ["sha256-" + "a" * 64]),
        ]
        manifests = {
            subject: image_index(),
            referrer: image_manifest(subject=subject),
            wrapper: image_index(referrer),
        }
        manifests[subject]["manifests"] = [descriptor(digest("d"))]
        versions.append(raw_version(4, digest("d"), self.old))
        manifests[digest("d")] = image_manifest()

        plan = retention.build_plan(FakeApi(versions, manifests), self.now)

        self.assertEqual(
            {subject, digest("d")},
            {item["digest"] for item in plan["policy_candidates"]},
        )

    def test_recently_untagged_version_uses_updated_time_for_the_age_floor(self):
        version = digest("a")
        api = FakeApi(
            [raw_version(1, version, self.old, updated=self.young)],
            {version: image_manifest()},
        )

        plan = retention.build_plan(api, self.now)

        self.assertEqual([], plan["policy_candidates"])
        self.assertEqual(1, plan["counts"]["unreachable_inside_age_floor"])

    def test_registry_failure_fails_the_whole_plan(self):
        image = digest("a")
        api = FakeApi(
            [raw_version(1, image, self.old, ["latest"])],
            {image: retention.RetentionError("registry unavailable")},
        )

        with self.assertRaisesRegex(retention.RetentionError, "registry unavailable"):
            retention.build_plan(api, self.now)

    def test_malformed_or_unsupported_manifest_evidence_fails_closed(self):
        image = digest("a")
        invalid_manifests = {
            "empty object": {},
            "wrong schema": {
                "schemaVersion": 1,
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
            },
            "unknown media": {"schemaVersion": 2, "mediaType": "application/example"},
            "missing index children": {
                "schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "manifests": [],
            },
            "malformed child descriptor": {
                "schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "manifests": [{"mediaType": "application/vnd.oci.image.manifest.v1+json"}],
            },
            "malformed subject": {
                **image_manifest(),
                "subject": {"mediaType": "application/vnd.oci.image.index.v1+json", "digest": digest("b")},
            },
            "unsupported subject": {
                **image_manifest(),
                "subject": descriptor(digest("b"), "application/example"),
            },
        }
        for name, manifest in invalid_manifests.items():
            with self.subTest(name=name):
                api = FakeApi([raw_version(1, image, self.old)], {image: manifest})
                with self.assertRaises(retention.RetentionError):
                    retention.build_plan(api, self.now)

    def test_missing_referenced_manifest_or_subject_fails_closed(self):
        image = digest("a")
        cases = [
            image_index(digest("b")),
            image_manifest(subject=digest("b")),
        ]
        for manifest in cases:
            with self.subTest(manifest=manifest["mediaType"]):
                api = FakeApi([raw_version(1, image, self.old)], {image: manifest})
                with self.assertRaisesRegex(retention.RetentionError, "absent from inventory"):
                    retention.build_plan(api, self.now)

    def test_invalid_or_duplicate_inventory_is_rejected(self):
        invalid = raw_version(1, "latest", self.old)
        with self.assertRaisesRegex(retention.RetentionError, "invalid package digest"):
            retention.parse_versions([invalid])

        repeated = raw_version(1, digest("a"), self.old)
        with self.assertRaisesRegex(retention.RetentionError, "duplicate"):
            retention.parse_versions([repeated, repeated])

    def test_plan_hash_detects_tampering(self):
        image = digest("a")
        api = FakeApi([raw_version(1, image, self.old, ["latest"])], {image: image_manifest()})
        plan = retention.build_plan(api, self.now)
        plan["minimum_age_days"] = 1

        with self.assertRaisesRegex(retention.RetentionError, "hash does not match"):
            retention.verify_plan(plan)


if __name__ == "__main__":
    unittest.main()
