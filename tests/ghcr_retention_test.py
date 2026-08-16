#!/usr/bin/env python3

import hashlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ghcr_retention", ROOT / "scripts/ghcr_retention.py")
retention = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = retention
SPEC.loader.exec_module(retention)


def blob_digest(character):
    return "sha256:" + character * 64


def encode_manifest(value):
    raw = json.dumps(value, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(raw).hexdigest(), raw


def descriptor(digest, raw, media_type="application/vnd.oci.image.manifest.v1+json"):
    return {"mediaType": media_type, "digest": digest, "size": len(raw)}


def image_manifest(subject=None, marker="0"):
    value = {
        "schemaVersion": 2,
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": blob_digest(marker),
            "size": 1,
        },
        "layers": [],
    }
    if subject is not None:
        value["subject"] = descriptor(
            subject[0], subject[1], "application/vnd.oci.image.index.v1+json"
        )
    return encode_manifest(value)


def image_index(*children):
    return encode_manifest(
        {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "manifests": [descriptor(child[0], child[1], child[2]) for child in children],
        }
    )


def artifact_manifest(subject):
    return encode_manifest(
        {
            "schemaVersion": 2,
            "mediaType": retention.ARTIFACT_MEDIA_TYPE,
            "artifactType": "application/vnd.example.provenance",
            "blobs": [],
            "subject": descriptor(subject[0], subject[1], subject[2]),
        }
    )


def raw_version(version_id, name, created, tags=(), updated=None):
    return {
        "id": version_id,
        "name": name,
        "created_at": created,
        "updated_at": updated or created,
        "metadata": {"container": {"tags": list(tags)}},
    }


class FakeRegistry:
    def __init__(self, manifests):
        self.manifests = manifests

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
        self.run_id = 1000

    def source(self, ref="refs/heads/main"):
        self.run_id += 1
        return retention.source_identity(
            repository=retention.REPOSITORY,
            ref=ref,
            run_id=self.run_id,
            run_attempt=1,
            head_sha=f"{self.run_id:040x}",
        )

    def evidence_for(self, plan):
        source = plan["source"]
        artifact = {
            "id": source["run_id"] + 10000,
            "name": source["artifact_name"],
            "digest": "sha256:" + "a" * 64,
            "size_in_bytes": 100,
        }
        expected = {"status": "selected", "source": source, "artifact": artifact}
        return expected, {**expected, "plan": plan}

    def build(
        self,
        versions,
        manifests,
        now=None,
        prior=None,
        source=None,
        expected=None,
        evidence=None,
    ):
        if prior is not None and evidence is None:
            expected_from_plan, evidence = self.evidence_for(prior)
            if expected is None:
                expected = expected_from_plan
        return retention.build_plan(
            versions,
            FakeRegistry(manifests),
            now or self.now,
            source or self.source(),
            evidence,
            expected,
        )

    def continuous_plan(self, versions, manifests):
        prior = None
        observed = datetime(2026, 7, 1, tzinfo=timezone.utc)
        while observed < self.now:
            active_versions = [
                version
                for version in versions
                if retention.parse_time(version["created_at"]) <= observed
            ]
            active_manifests = {
                version["name"]: manifests[version["name"]] for version in active_versions
            }
            prior = self.build(active_versions, active_manifests, observed, prior)
            observed += timedelta(days=7)
        return self.build(versions, manifests, self.now, prior)

    def test_preserves_tagged_graph_and_subject_linked_provenance(self):
        platform = image_manifest(marker="1")
        root = image_index((platform[0], platform[1], "application/vnd.oci.image.manifest.v1+json"))
        attestation = artifact_manifest(
            (root[0], root[1], "application/vnd.oci.image.index.v1+json")
        )
        wrapper = image_index(
            (attestation[0], attestation[1], retention.ARTIFACT_MEDIA_TYPE)
        )
        old_orphan = image_manifest(marker="2")
        young_orphan = image_manifest(marker="3")
        versions = [
            raw_version(1, root[0], self.old, ["base-commit"]),
            raw_version(2, platform[0], self.old),
            raw_version(3, attestation[0], self.old),
            raw_version(4, wrapper[0], self.old, ["sha256-" + "a" * 64]),
            raw_version(5, old_orphan[0], self.old),
            raw_version(6, young_orphan[0], self.young),
        ]
        manifests = dict((item[0], item[1]) for item in [platform, root, attestation, wrapper, old_orphan, young_orphan])

        plan = self.continuous_plan(versions, manifests)

        self.assertEqual(
            {old_orphan[0]},
            {item["digest"] for item in plan["policy_candidates"]},
        )
        self.assertEqual(4, plan["counts"]["reachable"])
        self.assertEqual(2, plan["counts"]["reachable_untagged_dependencies"])
        self.assertEqual(1, plan["counts"]["synthetic_attestation_tagged"])
        self.assertFalse(plan["pruning_authorized"])
        self.assertEqual(plan["plan_sha256"], retention.verify_plan(plan))

    def test_missing_prior_observation_produces_zero_candidates(self):
        orphan = image_manifest()
        plan = self.build(
            [raw_version(1, orphan[0], self.old)],
            {orphan[0]: orphan[1]},
        )

        self.assertEqual([], plan["policy_candidates"])
        self.assertEqual("missing_prior_evidence", plan["observation_chain"]["status"])
        self.assertEqual(
            "2026-08-16T00:00:00Z",
            plan["untagged_classifications"][0]["first_observed_untagged"],
        )

    def test_synthetic_attestation_tag_does_not_make_subject_a_release_root(self):
        platform = image_manifest(marker="4")
        subject = image_index(
            (platform[0], platform[1], "application/vnd.oci.image.manifest.v1+json")
        )
        referrer = artifact_manifest(
            (subject[0], subject[1], "application/vnd.oci.image.index.v1+json")
        )
        wrapper = image_index(
            (referrer[0], referrer[1], retention.ARTIFACT_MEDIA_TYPE)
        )
        versions = [
            raw_version(1, subject[0], self.old),
            raw_version(2, platform[0], self.old),
            raw_version(3, referrer[0], self.old),
            raw_version(4, wrapper[0], self.old, ["sha256-" + "a" * 64]),
        ]
        manifests = dict(
            (item[0], item[1]) for item in [platform, subject, referrer, wrapper]
        )

        plan = self.continuous_plan(versions, manifests)

        self.assertEqual(
            {subject[0], platform[0]},
            {item["digest"] for item in plan["policy_candidates"]},
        )

    def test_old_version_newly_untagged_resets_the_floor_despite_updated_at(self):
        image = image_manifest()
        tagged = [raw_version(1, image[0], self.old, ["latest"], updated=self.old)]
        prior = self.build(tagged, {image[0]: image[1]}, self.now - timedelta(days=7))
        untagged = [raw_version(1, image[0], self.old, updated=self.old)]

        plan = self.build(untagged, {image[0]: image[1]}, prior=prior)

        self.assertEqual([], plan["policy_candidates"])
        self.assertEqual(1, plan["counts"]["unreachable_inside_age_floor"])

    def test_stale_tampered_or_identity_discontinuous_prior_resets_floor(self):
        image = image_manifest()
        versions = [raw_version(1, image[0], self.old)]
        manifests = {image[0]: image[1]}
        old_plan = self.build(versions, manifests, datetime(2026, 7, 1, tzinfo=timezone.utc))
        recent_plan = self.build(versions, manifests, self.now - timedelta(days=7), old_plan)
        tampered = json.loads(json.dumps(recent_plan))
        tampered["untagged_classifications"][0]["first_observed_untagged"] = self.old
        discontinuous = json.loads(json.dumps(recent_plan))
        discontinuous["untagged_classifications"][0]["id"] = 2
        discontinuous["plan_sha256"] = retention.sha256(
            {key: value for key, value in discontinuous.items() if key != "plan_sha256"}
        )

        for name, prior in {
            "stale": old_plan,
            "tampered": tampered,
            "identity discontinuity": discontinuous,
        }.items():
            with self.subTest(name=name):
                plan = self.build(versions, manifests, prior=prior)
                self.assertEqual([], plan["policy_candidates"])
                expected = (
                    "continued"
                    if name == "identity discontinuity"
                    else "untrusted_or_discontinuous_prior_evidence"
                )
                self.assertEqual(expected, plan["observation_chain"]["status"])

    def test_replayed_penultimate_plan_cannot_satisfy_latest_run_identity(self):
        image = image_manifest(marker="5")
        versions = [raw_version(1, image[0], self.old)]
        manifests = {image[0]: image[1]}
        prior = None
        plans = []
        observed = datetime(2026, 7, 1, tzinfo=timezone.utc)
        while observed < self.now:
            prior = self.build(versions, manifests, observed, prior)
            plans.append(prior)
            observed += timedelta(days=7)
        expected_latest, _ = self.evidence_for(plans[-1])
        _, replayed_evidence = self.evidence_for(plans[-2])

        plan = self.build(
            versions,
            manifests,
            evidence=replayed_evidence,
            expected=expected_latest,
        )

        self.assertEqual([], plan["policy_candidates"])
        self.assertEqual(
            "untrusted_or_discontinuous_prior_evidence",
            plan["observation_chain"]["status"],
        )

    def test_time_rollback_and_non_main_source_reset_observation_age(self):
        image = image_manifest(marker="6")
        versions = [raw_version(1, image[0], self.old)]
        manifests = {image[0]: image[1]}
        future_prior = self.build(versions, manifests, self.now)

        rollback = self.build(
            versions,
            manifests,
            self.now - timedelta(days=1),
            future_prior,
        )
        non_main = self.build(
            versions,
            manifests,
            prior=future_prior,
            source=self.source("refs/heads/review"),
        )

        self.assertEqual([], rollback["policy_candidates"])
        self.assertEqual(
            "untrusted_or_discontinuous_prior_evidence",
            rollback["observation_chain"]["status"],
        )
        self.assertEqual([], non_main["policy_candidates"])
        self.assertEqual("non_main_source", non_main["observation_chain"]["status"])
        self.assertEqual("refs/heads/review", non_main["source"]["ref"])

    def test_non_main_prior_command_removes_stale_workspace_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            expected = Path(directory) / "expected.json"
            evidence = Path(directory) / "evidence.json"
            expected.write_text('{"forged":true}')
            evidence.write_text('{"forged":true}')

            result = retention.main(
                [
                    "prior-evidence",
                    "--repository",
                    retention.REPOSITORY,
                    "--ref",
                    "refs/heads/review",
                    "--current-run-id",
                    "2000",
                    "--expected-output",
                    str(expected),
                    "--evidence-output",
                    str(evidence),
                ]
            )

            self.assertEqual(0, result)
            self.assertFalse(evidence.exists())
            self.assertEqual("reset", json.loads(expected.read_text())["status"])

    def test_registry_failure_fails_the_whole_plan(self):
        image = image_manifest()
        with self.assertRaisesRegex(retention.RetentionError, "registry unavailable"):
            self.build(
                [raw_version(1, image[0], self.old, ["latest"])],
                {image[0]: retention.RetentionError("registry unavailable")},
            )

    def test_manifest_digest_mismatch_fails_closed(self):
        image = image_manifest()
        changed = image[1] + b"\n"
        with self.assertRaisesRegex(retention.RetentionError, "digest mismatch"):
            self.build([raw_version(1, image[0], self.old)], {image[0]: changed})

    def test_referenced_manifest_and_subject_size_mismatches_fail_closed(self):
        child = image_manifest()
        bad_index_value = {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "manifests": [
                {
                    **descriptor(child[0], child[1]),
                    "size": len(child[1]) + 1,
                }
            ],
        }
        bad_index = encode_manifest(bad_index_value)
        subject = image_index(
            (child[0], child[1], "application/vnd.oci.image.manifest.v1+json")
        )
        bad_artifact_value = {
            "schemaVersion": 2,
            "mediaType": retention.ARTIFACT_MEDIA_TYPE,
            "artifactType": "application/example",
            "blobs": [],
            "subject": {
                **descriptor(
                    subject[0], subject[1], "application/vnd.oci.image.index.v1+json"
                ),
                "size": len(subject[1]) + 1,
            },
        }
        bad_artifact = encode_manifest(bad_artifact_value)
        cases = [
            (
                [raw_version(1, bad_index[0], self.old), raw_version(2, child[0], self.old)],
                {bad_index[0]: bad_index[1], child[0]: child[1]},
            ),
            (
                [
                    raw_version(1, subject[0], self.old),
                    raw_version(2, child[0], self.old),
                    raw_version(3, bad_artifact[0], self.old),
                ],
                {subject[0]: subject[1], child[0]: child[1], bad_artifact[0]: bad_artifact[1]},
            ),
        ]
        for versions, manifests in cases:
            with self.subTest(version=versions[0]["name"]):
                with self.assertRaisesRegex(retention.RetentionError, "size does not match"):
                    self.build(versions, manifests)

    def test_referenced_manifest_media_type_mismatch_fails_closed(self):
        child = image_manifest()
        index = image_index((child[0], child[1], retention.ARTIFACT_MEDIA_TYPE))
        with self.assertRaisesRegex(retention.RetentionError, "mediaType does not match"):
            self.build(
                [raw_version(1, index[0], self.old), raw_version(2, child[0], self.old)],
                {index[0]: index[1], child[0]: child[1]},
            )

    def test_malformed_or_unsupported_manifest_evidence_fails_closed(self):
        invalid_values = {
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
        }
        for name, value in invalid_values.items():
            with self.subTest(name=name):
                manifest = encode_manifest(value)
                with self.assertRaises(retention.RetentionError):
                    self.build(
                        [raw_version(1, manifest[0], self.old)],
                        {manifest[0]: manifest[1]},
                    )

    def test_missing_referenced_manifest_fails_closed(self):
        child = image_manifest()
        index = image_index(
            (child[0], child[1], "application/vnd.oci.image.manifest.v1+json")
        )
        with self.assertRaisesRegex(retention.RetentionError, "absent from inventory"):
            self.build([raw_version(1, index[0], self.old)], {index[0]: index[1]})

    def test_invalid_or_duplicate_inventory_is_rejected(self):
        with self.assertRaisesRegex(retention.RetentionError, "invalid package digest"):
            retention.parse_versions([raw_version(1, "latest", self.old)])
        repeated = raw_version(1, blob_digest("a"), self.old)
        with self.assertRaisesRegex(retention.RetentionError, "duplicate"):
            retention.parse_versions([repeated, repeated])

    def test_plan_hash_detects_tampering(self):
        image = image_manifest()
        plan = self.build(
            [raw_version(1, image[0], self.old, ["latest"])],
            {image[0]: image[1]},
        )
        plan["minimum_age_days"] = 1
        with self.assertRaisesRegex(retention.RetentionError, "hash does not match"):
            retention.verify_plan(plan)


class ExternalAdapterTests(unittest.TestCase):
    def completed(self, stdout=b"", stderr=b""):
        return subprocess.CompletedProcess([], 0, stdout=stdout, stderr=stderr)

    def archive(self, entries=None):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as bundle:
            for name, value in entries or [("ghcr-retention-plan.json", b'{"plan":true}')]:
                bundle.writestr(name, value)
        return output.getvalue()

    @mock.patch.object(retention.subprocess, "run")
    def test_github_pagination_accepts_slurped_pages_and_single_page_shape(self, run):
        for payload in ([[{"id": 1}], [{"id": 2}]], [{"id": 1}]):
            with self.subTest(payload=payload):
                run.return_value = self.completed(json.dumps(payload).encode())
                result = retention.GitHubApi().package_versions()
                self.assertEqual([1] if len(payload) == 1 else [1, 2], [item["id"] for item in result])
                command = run.call_args.args[0]
                self.assertIn("--paginate", command)
                self.assertIn("--slurp", command)

    @mock.patch.object(retention.subprocess, "run")
    def test_invalid_output_and_timeout_are_typed_failures(self, run):
        run.return_value = self.completed(b"not json")
        with self.assertRaisesRegex(retention.RetentionError, "invalid JSON"):
            retention.GitHubApi().package_versions()
        run.side_effect = subprocess.TimeoutExpired(["gh"], 60)
        with self.assertRaisesRegex(retention.RetentionError, "external command failed: gh"):
            retention.GitHubApi().package_versions()
        run.side_effect = subprocess.CalledProcessError(1, ["gh"], stderr=b"unavailable")
        with self.assertRaisesRegex(retention.RetentionError, "external command failed: gh"):
            retention.GitHubApi().package_versions()

    @mock.patch.object(retention.subprocess, "run")
    def test_invalid_pagination_and_duplicate_json_keys_fail_closed(self, run):
        for payload in (b'[[{"id":1}],{"id":2}]', b'{"id":1,"id":2}'):
            with self.subTest(payload=payload):
                run.return_value = self.completed(payload)
                with self.assertRaises(retention.RetentionError):
                    retention.GitHubApi().package_versions()

    def test_non_finite_json_numbers_fail_closed_at_every_parser_boundary(self):
        for value in (b"NaN", b"Infinity", b"-Infinity", b"1e999", b'{"value":NaN}'):
            with self.subTest(value=value):
                with self.assertRaisesRegex(retention.RetentionError, "invalid JSON"):
                    retention.parse_json(value, "test")

    @mock.patch.object(retention.CommandRunner, "run")
    @mock.patch.object(retention.GitHubApi, "_json_api")
    def test_latest_successful_artifact_is_bound_to_run_and_api_digest(self, json_api, run):
        archive = self.archive()
        source = retention.source_identity(
            repository=retention.REPOSITORY,
            ref="refs/heads/main",
            run_id=800,
            run_attempt=2,
            head_sha="b" * 40,
        )
        json_api.side_effect = [
            {
                "workflow_runs": [
                    {
                        "id": 800,
                        "run_attempt": 2,
                        "head_sha": "b" * 40,
                        "head_branch": "main",
                        "status": "completed",
                        "conclusion": "success",
                        "repository": {"full_name": retention.REPOSITORY},
                        "head_repository": {"full_name": retention.REPOSITORY},
                    }
                ]
            },
            {
                "artifacts": [
                    {
                        "id": 900,
                        "name": source["artifact_name"],
                        "digest": "sha256:" + hashlib.sha256(archive).hexdigest(),
                        "size_in_bytes": len(archive),
                        "expired": False,
                        "workflow_run": {
                            "id": 800,
                            "head_branch": "main",
                            "head_sha": "b" * 40,
                        },
                    }
                ]
            },
        ]
        run.return_value = archive

        expected, evidence = retention.GitHubApi().previous_plan_evidence(
            retention.REPOSITORY, 801
        )

        self.assertEqual(source, expected["source"])
        self.assertEqual(900, expected["artifact"]["id"])
        self.assertEqual(expected["artifact"], evidence["artifact"])
        runs_endpoint = json_api.call_args_list[0].args[0]
        self.assertIn("branch=main", runs_endpoint)
        self.assertIn("status=success", runs_endpoint)
        self.assertIn("per_page=1", runs_endpoint)

    @mock.patch.object(retention.CommandRunner, "run")
    @mock.patch.object(retention.GitHubApi, "_json_api")
    def test_artifact_digest_mismatch_fails_closed(self, json_api, run):
        archive = self.archive()
        source = retention.source_identity(
            repository=retention.REPOSITORY,
            ref="refs/heads/main",
            run_id=800,
            run_attempt=1,
            head_sha="c" * 40,
        )
        json_api.side_effect = [
            {
                "workflow_runs": [
                    {
                        "id": 800,
                        "run_attempt": 1,
                        "head_sha": "c" * 40,
                        "head_branch": "main",
                        "status": "completed",
                        "conclusion": "success",
                        "repository": {"full_name": retention.REPOSITORY},
                        "head_repository": {"full_name": retention.REPOSITORY},
                    }
                ]
            },
            {
                "artifacts": [
                    {
                        "id": 900,
                        "name": source["artifact_name"],
                        "digest": "sha256:" + "d" * 64,
                        "size_in_bytes": len(archive),
                        "expired": False,
                        "workflow_run": {
                            "id": 800,
                            "head_branch": "main",
                            "head_sha": "c" * 40,
                        },
                    }
                ]
            },
        ]
        run.return_value = archive

        with self.assertRaisesRegex(retention.RetentionError, "digest does not match"):
            retention.GitHubApi().previous_plan_evidence(retention.REPOSITORY, 801)

    def test_artifact_archive_requires_one_exact_plan_entry(self):
        cases = [
            self.archive([("nested/ghcr-retention-plan.json", b"{}")]),
            self.archive(
                [("ghcr-retention-plan.json", b"{}"), ("unexpected.json", b"{}")]
            ),
        ]
        for archive in cases:
            with self.subTest(entries=len(zipfile.ZipFile(io.BytesIO(archive)).infolist())):
                with self.assertRaisesRegex(retention.RetentionError, "exactly the expected plan"):
                    retention.extract_plan_archive(archive)

    @mock.patch.object(retention.subprocess, "run")
    def test_registry_adapter_binds_digest_and_strips_workflow_credentials(self, run):
        manifest = image_manifest()
        run.return_value = self.completed(manifest[1])
        credential_keys = {
            "ACTIONS_RUNTIME_TOKEN",
            "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
            "ACTIONS_ID_TOKEN_REQUEST_URL",
            "GH_TOKEN",
            "GITHUB_TOKEN",
        }
        self.assertEqual(credential_keys, retention.SECRET_ENVIRONMENT_KEYS)
        with mock.patch.dict(
            os.environ,
            {**dict.fromkeys(credential_keys, "secret"), "UNRELATED": "kept"},
        ):
            self.assertEqual(manifest[1], retention.RegistryApi().manifest(manifest[0]))

        environment = run.call_args.kwargs["env"]
        for name in credential_keys:
            self.assertNotIn(name, environment)
        self.assertEqual("kept", environment["UNRELATED"])

    @mock.patch.object(retention.subprocess, "run")
    def test_registry_invalid_output_and_timeout_fail_closed(self, run):
        invalid = b'{"schemaVersion":NaN}'
        requested = "sha256:" + hashlib.sha256(invalid).hexdigest()
        run.return_value = self.completed(invalid)
        with self.assertRaisesRegex(retention.RetentionError, "invalid JSON"):
            retention.RegistryApi().manifest(requested)
        run.side_effect = subprocess.TimeoutExpired(["docker"], 60)
        with self.assertRaisesRegex(retention.RetentionError, "external command failed: docker"):
            retention.RegistryApi().manifest(requested)


if __name__ == "__main__":
    unittest.main()
