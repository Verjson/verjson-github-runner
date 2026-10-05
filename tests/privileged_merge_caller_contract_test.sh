#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
primary="${root}/.github/workflows/ai-privileged-merge.yml"
retry="${root}/.github/workflows/ai-promotion-retry.yml"

printf '%s  %s\n' \
  '987f8e5b7ff09a30ef345f7f23fff55e927e03b64945b1969306da34f76f2e24' "${primary}" \
  'a63add3aa7dcd326b86c963212d6b68f4aa97ccc0e1d8cf9fc3dc3c1ada8a0b6' "${retry}" \
  | sha256sum --check --strict >/dev/null

python3 - "${primary}" "${retry}" "${root}/tests/contract_pins.json" <<'PY'
import json
import sys
import yaml

primary_text = open(sys.argv[1], encoding="utf-8").read()
retry_text = open(sys.argv[2], encoding="utf-8").read()
primary = yaml.safe_load(primary_text)
retry = yaml.safe_load(retry_text)
# Shared with tests/ai_review_caller_test.py: one pin per family, one file.
contract = json.loads(open(sys.argv[3], encoding="utf-8").read())["ai-callers"]
permissions = {
    "actions": "write",
    "checks": "read",
    "contents": "read",
    "issues": "read",
    "pull-requests": "read",
}
required_checks = [
    {
        "name": "shell-tests",
        "app_id": 15368,
        "workflow_id": 319611670,
        "workflow_path": ".github/workflows/test.yml",
    },
    {
        "name": "changelog / validate",
        "app_id": 15368,
        "workflow_id": 325336751,
        "workflow_path": ".github/workflows/changelog.yml",
    },
]

assert primary["permissions"] == permissions
assert retry["permissions"] == permissions
assert primary["jobs"]["privileged_merge"]["uses"] == (
    f"Verjson/.github/.github/workflows/ai-privileged-merge.yml@{contract}"
)
assert retry["jobs"]["retry"]["uses"] == (
    f"Verjson/.github/.github/workflows/ai-promotion-retry.yml@{contract}"
)
# Custody moved into the callee under ADR 0166/0180: the merge App private key
# is resolved from the `merge-app` environment by the callee job, so the caller
# has no scope in which to name it. The control that replaced the explicit
# grant is the environment binding, so assert that.
assert primary["jobs"]["privileged_merge"]["secrets"] == "inherit"
assert retry["jobs"]["retry"]["secrets"] == "inherit"
assert primary["jobs"]["privileged_merge"]["with"]["merge_environment"] == "merge-app"
assert retry["jobs"]["retry"]["with"]["merge_environment"] == "merge-app"
assert json.loads(primary["jobs"]["privileged_merge"]["with"]["required_checks"]) == required_checks
assert json.loads(retry["jobs"]["retry"]["with"]["required_checks"]) == required_checks
for workflow, source in ((primary, primary_text), (retry, retry_text)):
    # `secrets: inherit` hands the callee every organization secret without
    # the caller naming one, so no string assertion over this file can bound
    # what it grants. The sha256 digests above are that control now: these are
    # generated files, and a digest change means the generator's output changed
    # or somebody hand-edited a privileged caller. The two checks below are
    # cosmetic — they catch a hand-added secret block, nothing more.
    # `actions: write` became part of the contract with Verjson/.github#1583
    # (ADR 0207: it backs a post-merge cleanup of the consumed arm-receipt
    # artifact; `issues: read` backs a closingIssuesReferences read to surface
    # issues the terminal merge silently fails to auto-close). The
    # `permissions` equality assert above, not this loop, is what bounds it.
    assert "ORG_ADMIN_TOKEN" not in source
    assert "MERGE_APP_PRIVATE_KEY" not in source
    assert "generated-artifacts / validate" not in source
PY

echo "privileged merge generated caller contract passed"
