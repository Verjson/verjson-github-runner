#!/usr/bin/env python3
import hashlib
import json
import re
import unittest
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
# This repository is on three contracts at once, so one `CONTRACT` constant
# cannot describe it and a test built on one silently asserts the wrong thing
# about two of them. The pins live in tests/contract_pins.json so that the shell
# contract test reads the same values; a second copy is how this repository last
# asserted the wrong contract.
_PINS = json.loads((ROOT / 'tests/contract_pins.json').read_text())
AI_CALLER_CONTRACT = _PINS['ai-callers']
AI_REVIEW_CONTRACT = _PINS['ai-review-merge']
GENERATED_ARTIFACTS_CONTRACT = _PINS['generated-artifacts']
CONTAINER_CONTRACT = _PINS['containers']
CONTAINER_DEPLOYMENT_CONTRACT = _PINS['container-deployment']

# Under `secrets: inherit` the caller names no secret, so nothing in its text
# bounds what it hands the callee. Byte identity is what is left: these are
# generated files, and a digest change means the generator's output changed or
# somebody hand-edited a privileged caller. The privileged-merge pair is pinned
# the same way in tests/privileged_merge_caller_contract_test.sh.
GENERATED_CALLER_DIGESTS = {
    '.github/workflows/ai-review-merge.yml':
        '07fd35d64d6f0647e290ee3e863ced72a4b4bd5351515a17f362f994623bf2eb',
    '.github/workflows/gate-rearm.yml':
        'f9d05ce32c449af5bfd4c8050dc1c7be8745b41504b38f8842e3aa9a5d1c7c7f',
    '.github/workflows/ai-review-lifecycle-rearm.yml':
        '252c38a04883b42700bdf2d0cab76f3390d285d242f89a2eebb0d0ba80cfae32',
    '.github/workflows/ai-review-label-rearm.yml':
        '4387bb0a0b4b38b9c98de73f6adf02835ff2f574ecce4398ed618180e7a95cf3',
}


class ReviewCallerTest(unittest.TestCase):
    def test_rearm_callers_own_only_their_assigned_pull_request_events(self):
        callers = {
            'gate-rearm.yml': {'opened', 'reopened', 'synchronize'},
            'ai-review-lifecycle-rearm.yml': {
                'ready_for_review', 'converted_to_draft', 'edited', 'unlabeled'},
            'ai-review-label-rearm.yml': {'labeled'},
        }
        for filename, expected_events in callers.items():
            with self.subTest(caller=filename):
                caller = yaml.safe_load((ROOT / '.github/workflows' / filename).read_text())
                triggers = caller[True]
                self.assertEqual(
                    set(triggers),
                    {'pull_request_target', 'workflow_call'} if filename == 'gate-rearm.yml'
                    else {'pull_request_target'},
                    f'{filename} declares an unexpected workflow trigger')
                self.assertEqual(
                    set(triggers['pull_request_target']['types']), expected_events,
                    f'{filename} owns events outside its assigned partition')

    def test_gate_rearm_exposes_required_string_environment_input(self):
        gate = yaml.safe_load((ROOT / '.github/workflows/gate-rearm.yml').read_text())
        environment_input = gate[True]['workflow_call']['inputs']['ai_review_environment']
        self.assertEqual(
            environment_input['required'], True)
        self.assertEqual(environment_input['type'], 'string')
        self.assertTrue(environment_input['description'])

    def test_rearm_callers_keep_the_shared_permissions_and_call_contract(self):
        expected_workflow_permissions = {
            'gate-rearm.yml': {'contents': 'read'},
            'ai-review-lifecycle-rearm.yml': {'actions': 'read', 'contents': 'read'},
            'ai-review-label-rearm.yml': {'actions': 'read', 'contents': 'read'},
        }
        expected_job_permissions = {
            'actions': 'write',
            'checks': 'write',
            'contents': 'read',
            'issues': 'write',
            'pull-requests': 'write',
        }
        callers = (
            'gate-rearm.yml',
            'ai-review-lifecycle-rearm.yml',
            'ai-review-label-rearm.yml',
        )
        expected_uses = {
            'gate-rearm.yml':
                'Verjson/.github/.github/workflows/gate-rearm.yml@' + AI_CALLER_CONTRACT,
            'ai-review-lifecycle-rearm.yml': './.github/workflows/gate-rearm.yml',
            'ai-review-label-rearm.yml':
                'Verjson/.github/.github/workflows/gate-rearm.yml@' + AI_CALLER_CONTRACT,
        }
        for filename in callers:
            with self.subTest(caller=filename):
                caller = yaml.safe_load((ROOT / '.github/workflows' / filename).read_text())
                job = caller['jobs']['rearm']
                self.assertEqual(caller['permissions'], expected_workflow_permissions[filename])
                self.assertEqual(job['permissions'], expected_job_permissions)
                self.assertEqual(job['uses'], expected_uses[filename])
                self.assertEqual(job['secrets'], 'inherit')
                self.assertEqual(job['with'], {'ai_review_environment': 'ai-review-app'})

    def test_review_dispatch_keeps_exact_head_inputs_with_repaired_immutable_contract(self):
        caller = yaml.safe_load((ROOT / '.github/workflows/ai-review-merge.yml').read_text())
        job = caller['jobs']['review']
        self.assertEqual(job['uses'], 'Verjson/.github/.github/workflows/ai-review-merge.yml@' + AI_REVIEW_CONTRACT)
        self.assertEqual(job['with']['expected_head_sha'], '${{ inputs.expected_head_sha }}')
        self.assertEqual(job['with']['authorization_check_id'], '${{ inputs.authorization_check_id }}')
        self.assertEqual(job['with']['arm_run_id'], '${{ inputs.arm_run_id }}')


    def test_every_hub_caller_is_pinned_to_its_declared_family(self):
        """No caller drifts to a SHA this repository has not named.

        The three constants above are the whole inventory. A caller repinned
        without updating them lands here rather than in a reviewer's memory,
        which is the failure this repository has already had twice.
        """
        families = {
            'ai-privileged-merge.yml': AI_CALLER_CONTRACT,
            'ai-promotion-retry.yml': AI_CALLER_CONTRACT,
            'ai-review-merge.yml': AI_REVIEW_CONTRACT,
            'gate-rearm.yml': AI_CALLER_CONTRACT,
            'generated-artifacts.yml': GENERATED_ARTIFACTS_CONTRACT,
            'container-candidate.yml': CONTAINER_CONTRACT,
            'container-candidate-publish.yml': CONTAINER_CONTRACT,
            'container-release.yml': CONTAINER_CONTRACT,
            'container-deployment.yml': CONTAINER_DEPLOYMENT_CONTRACT,
            'container-deployment-review-producer.yml': CONTAINER_DEPLOYMENT_CONTRACT,
        }
        # A narrow callee pattern does not fail on a name it cannot match — it
        # skips it, so a caller named outside the pattern escapes the whole
        # check silently. Match permissively, then assert that every reference
        # to a hub workflow in the tree was one this pattern consumed.
        pattern = re.compile(
            r'Verjson/\.github/\.github/workflows/([A-Za-z0-9._-]+\.ya?ml)@([0-9a-f]{40})')
        any_reference = re.compile(r'Verjson/\.github/\.github/workflows/\S+')
        seen = set()
        for path in sorted((ROOT / '.github/workflows').glob('*.y*ml')):
            text = path.read_text()
            matched = {m.group(0) for m in pattern.finditer(text)}
            for reference in any_reference.findall(text):
                reference = reference.rstrip("'\",")
                self.assertTrue(
                    any(reference.startswith(m) or m.startswith(reference)
                        for m in matched),
                    f'{path.name} references {reference}, which is not a '
                    'pinned hub caller this test can check')
            for callee, sha in pattern.findall(text):
                seen.add(callee)
                self.assertIn(callee, families,
                              f'{path.name} calls unregistered {callee}@{sha}')
                self.assertEqual(
                    sha, families[callee],
                    f'{path.name} pins {callee} outside its declared family')
        self.assertEqual(seen, set(families),
                         'the family map lists a callee nothing invokes')

    def test_generated_ai_review_callers_are_byte_pinned(self):
        """A privileged caller cannot change without this test saying so."""
        for relative, expected in GENERATED_CALLER_DIGESTS.items():
            with self.subTest(caller=relative):
                digest = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
                self.assertEqual(
                    expected, digest,
                    f'{relative} changed; regenerate it with the canonical '
                    'generator and repin this digest deliberately')


if __name__ == '__main__':
    unittest.main()
