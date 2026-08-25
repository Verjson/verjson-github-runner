#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
primary="${root}/.github/workflows/ai-privileged-merge.yml"
retry="${root}/.github/workflows/ai-promotion-retry.yml"

printf '%s  %s\n' \
  '13791f1cebdf6800fa9a67504911f998f85b40e46056167a253f7992c80cf95a' "${primary}" \
  '546497fc6a096867657ed0d1101b51dffc494d24f3d5ecd41f4f585fb76234ce' "${retry}" \
  | sha256sum --check --strict >/dev/null

python3 - "${primary}" "${retry}" <<'PY'
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
for workflow, source in ((primary, primary_text), (retry, retry_text)):
    assert "ORG_ADMIN_TOKEN" not in source
    assert "secrets: inherit" not in source
    assert "write" not in workflow["permissions"].values()
PY

echo "privileged merge generated caller contract passed"
