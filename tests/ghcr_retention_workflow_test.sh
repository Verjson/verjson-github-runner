#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$root/.github/workflows/ghcr-retention.yml"

fail() {
  echo "ghcr retention workflow contract: $*" >&2
  exit 1
}

grep -Fq -- "- cron: '23 6 * * 1'" "$workflow" || fail "weekly dry-run schedule is missing"
grep -Fq 'workflow_dispatch:' "$workflow" || fail "manual dry-run trigger is missing"
grep -Fq 'packages: read' "$workflow" || fail "inventory lacks package read permission"
grep -Fq 'pruning_authorized' "$workflow" || fail "summary does not state authorization status"
grep -Fq 'persist-credentials: false' "$workflow" || fail "checkout persists GitHub credentials"
grep -Fq 'ghcr_retention.py inventory' "$workflow" || fail "token-scoped inventory step is missing"
grep -Fq -- '--prior-plan prior-observation/ghcr-retention-plan.json' "$workflow" \
  || fail "durable prior observation is not consumed"
grep -Fq "\"\$GITHUB_REF\" == 'refs/heads/main'" "$workflow" \
  || fail "prior observations are not restricted to the trusted main ref"

plan_step="$(sed -n '/- name: Build fail-closed retention plan/,/- name: Upload auditable dry-run plan/p' "$workflow")"
if grep -Fq 'GH_TOKEN' <<<"$plan_step"; then
  fail "registry inspection step inherits GH_TOKEN"
fi

for forbidden in \
  'packages: write' \
  'environment:' \
  'GHCR_PROTECTED_DIGESTS' \
  'GHCR_RETENTION_DELETE_ENABLED' \
  'DELETE ghcr.io' \
  'gh api --method DELETE' \
  'ghcr_retention.py apply' \
  'receipt'; do
  if grep -Fq "$forbidden" "$workflow"; then
    fail "read-only workflow contains forbidden mutation surface: $forbidden"
  fi
done

while IFS= read -r action; do
  [[ "$action" =~ @[0-9a-f]{40}$ ]] || fail "action is not pinned to an immutable SHA: $action"
done < <(sed -n 's/^[[:space:]]*- uses: \([^[:space:]#]*\).*/\1/p' "$workflow")

echo "ghcr retention workflow contract passed"
