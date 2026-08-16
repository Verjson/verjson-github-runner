#!/usr/bin/env python3

import importlib.util
import json
import sys
import tempfile
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


def raw_version(version_id, name, created, tags=()):
    return {
        "id": version_id,
        "name": name,
        "created_at": created,
        "updated_at": created,
        "metadata": {"container": {"tags": list(tags)}},
    }


class FakeApi:
    def __init__(self, versions, manifests):
        self.versions = versions
        self.manifests = manifests
        self.deleted = []

    def package_versions(self):
        return self.versions

    def manifest(self, name):
        value = self.manifests[name]
        if isinstance(value, Exception):
            raise value
        return value

    def delete_version(self, version_id):
        self.deleted.append(version_id)


class RetentionPlanTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 8, 16, tzinfo=timezone.utc)
        self.old = "2026-06-01T00:00:00Z"
        self.young = "2026-08-10T00:00:00Z"

    def test_preserves_tagged_and_deployed_graphs_and_selects_only_old_orphans(self):
        root = digest("a")
        platform = digest("b")
        attestation = digest("c")
        attestation_index = digest("d")
        deployed = digest("e")
        deployed_child = digest("f")
        old_orphan = digest("1")
        young_orphan = digest("2")
        versions = [
            raw_version(1, root, self.old, ["base-commit"]),
            raw_version(2, platform, self.old),
            raw_version(3, attestation, self.old),
            raw_version(4, attestation_index, self.old, ["sha256-" + "a" * 64]),
            raw_version(5, deployed, self.old),
            raw_version(6, deployed_child, self.old),
            raw_version(7, old_orphan, self.old),
            raw_version(8, young_orphan, self.young),
        ]
        manifests = {
            root: {"manifests": [{"digest": platform}]},
            platform: {},
            attestation: {"subject": {"digest": root}},
            attestation_index: {"manifests": [{"digest": attestation}]},
            deployed: {"manifests": [{"digest": deployed_child}]},
            deployed_child: {},
            old_orphan: {},
            young_orphan: {},
        }

        plan = retention.build_plan(FakeApi(versions, manifests), {deployed}, self.now)

        self.assertEqual([old_orphan], [item["digest"] for item in plan["delete_batch"]])
        self.assertEqual(6, plan["counts"]["reachable"])
        self.assertEqual(3, plan["counts"]["reachable_untagged_dependencies"])
        self.assertEqual(1, plan["counts"]["protected_untagged_deployment_or_rollback_roots"])
        self.assertEqual(2, plan["counts"]["unreachable_untagged"])
        self.assertEqual(1, plan["counts"]["synthetic_attestation_tagged"])
        self.assertTrue(plan["eligible_for_apply"])
        self.assertEqual(plan["plan_sha256"], retention.verify_plan(plan))

    def test_synthetic_attestation_tag_does_not_turn_its_subject_into_a_release_root(self):
        subject = digest("a")
        referrer = digest("b")
        wrapper = digest("c")
        versions = [
            raw_version(1, subject, self.old),
            raw_version(2, referrer, self.old),
            raw_version(3, wrapper, self.old, ["sha256-" + "a" * 64]),
        ]
        manifests = {
            subject: {},
            referrer: {"subject": {"digest": subject}},
            wrapper: {"manifests": [{"digest": referrer}]},
        }

        plan = retention.build_plan(FakeApi(versions, manifests), set(), self.now)

        self.assertEqual([subject], [item["digest"] for item in plan["delete_batch"]])
        self.assertFalse(plan["eligible_for_apply"])

    def test_missing_deployment_digest_fails_closed(self):
        image = digest("a")
        api = FakeApi([raw_version(1, image, self.old, ["latest"])], {image: {}})

        with self.assertRaisesRegex(retention.RetentionError, "protected deployment digest is absent"):
            retention.build_plan(api, {digest("b")}, self.now)

    def test_registry_failure_fails_the_whole_plan(self):
        image = digest("a")
        api = FakeApi(
            [raw_version(1, image, self.old, ["latest"])],
            {image: retention.RetentionError("registry unavailable")},
        )

        with self.assertRaisesRegex(retention.RetentionError, "registry unavailable"):
            retention.build_plan(api, set(), self.now)

    def test_invalid_inventory_is_rejected(self):
        invalid = raw_version(1, "latest", self.old)

        with self.assertRaisesRegex(retention.RetentionError, "invalid package digest"):
            retention.parse_versions([invalid])

    def test_protected_digest_parser_accepts_json_or_lines_and_rejects_bad_values(self):
        first = digest("a")
        second = digest("b")
        self.assertEqual({first, second}, retention.parse_protected_digests(json.dumps([first, second])))
        self.assertEqual({first, second}, retention.parse_protected_digests(first + "\n" + second))
        with self.assertRaisesRegex(retention.RetentionError, "invalid protected digest"):
            retention.parse_protected_digests("sha256:nope")


class RetentionApplyTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 8, 16, tzinfo=timezone.utc)
        self.old = "2026-06-01T00:00:00Z"
        self.protected = digest("a")
        self.orphan = digest("b")
        self.versions = [
            raw_version(1, self.protected, self.old, ["base-commit"]),
            raw_version(2, self.orphan, self.old),
        ]
        self.manifests = {self.protected: {}, self.orphan: {}}

    def test_apply_revalidates_and_writes_a_per_delete_receipt(self):
        api = FakeApi(self.versions, self.manifests)
        plan = retention.build_plan(api, {self.protected}, self.now)
        with tempfile.TemporaryDirectory() as directory:
            receipt_path = Path(directory) / "receipt.json"

            receipt = retention.apply_plan(
                api,
                plan,
                {self.protected},
                plan["plan_sha256"],
                retention.POLICY,
                receipt_path,
                self.now,
            )

            self.assertEqual([2], api.deleted)
            self.assertEqual("complete", receipt["status"])
            self.assertEqual(receipt, json.loads(receipt_path.read_text()))

    def test_apply_rejects_missing_policy_authorization(self):
        api = FakeApi(self.versions, self.manifests)
        plan = retention.build_plan(api, {self.protected}, self.now)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(retention.RetentionError, "policy is not enabled"):
                retention.apply_plan(
                    api,
                    plan,
                    {self.protected},
                    plan["plan_sha256"],
                    "disabled",
                    Path(directory) / "receipt.json",
                    self.now,
                )
        self.assertEqual([], api.deleted)

    def test_apply_rejects_tampered_plan_and_changed_inventory(self):
        api = FakeApi(self.versions, self.manifests)
        plan = retention.build_plan(api, {self.protected}, self.now)
        tampered = dict(plan)
        tampered["minimum_age_days"] = 1
        with self.assertRaisesRegex(retention.RetentionError, "hash does not match"):
            retention.verify_plan(tampered)

        api.versions.append(raw_version(3, digest("c"), self.old))
        api.manifests[digest("c")] = {}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(retention.RetentionError, "inventory changed"):
                retention.apply_plan(
                    api,
                    plan,
                    {self.protected},
                    plan["plan_sha256"],
                    retention.POLICY,
                    Path(directory) / "receipt.json",
                    self.now,
                )
        self.assertEqual([], api.deleted)


if __name__ == "__main__":
    unittest.main()
