#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
primary="${root}/.github/workflows/ai-privileged-merge.yml"
retry="${root}/.github/workflows/ai-promotion-retry.yml"

printf '%s  %s\n' \
  '3a1da44fa639ba162cd17e443c7574c0d4ff9a30bdc2f6051e9874977e67aa82' "${primary}" \
  '849351fbbff804078bed3a07ec47ba1ea9a0f8d6b966e52c309613fef2813cea' "${retry}" \
  | sha256sum --check --strict >/dev/null

python3 - "${primary}" "${retry}" <<'PY'
import json
import sys
import yaml

primary_text = open(sys.argv[1], encoding="utf-8").read()
retry_text = open(sys.argv[2], encoding="utf-8").read()
primary = yaml.safe_load(primary_text)
retry = yaml.safe_load(retry_text)
contract = "6462e0cc72f4d96baa4f8ff8a862db4af0f93db7"
permissions = {
    "actions": "read",
    "checks": "read",
    "contents": "read",
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
assert primary["jobs"]["privileged_merge"]["secrets"] == {
    "MERGE_APP_PRIVATE_KEY": "${{ secrets.MERGE_APP_PRIVATE_KEY }}"
}
assert retry["jobs"]["retry"]["secrets"] == {
    "MERGE_APP_PRIVATE_KEY": "${{ secrets.MERGE_APP_PRIVATE_KEY }}"
}
assert json.loads(primary["jobs"]["privileged_merge"]["with"]["required_checks"]) == required_checks
assert json.loads(retry["jobs"]["retry"]["with"]["required_checks"]) == required_checks
for workflow, source in ((primary, primary_text), (retry, retry_text)):
    assert "ORG_ADMIN_TOKEN" not in source
    assert "secrets: inherit" not in source
    assert "generated-artifacts / validate" not in source
    assert "write" not in workflow["permissions"].values()
PY

echo "privileged merge generated caller contract passed"
