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
grep -Fq 'actions: read' "$workflow" || fail "prior artifact access lacks actions-read permission"
grep -Fq 'packages: read' "$workflow" || fail "inventory lacks package read permission"
grep -Fq 'pruning_authorized' "$workflow" || fail "summary does not state authorization status"
grep -Fq 'persist-credentials: false' "$workflow" || fail "checkout persists GitHub credentials"
grep -Fq 'ghcr_retention.py inventory' "$workflow" || fail "token-scoped inventory step is missing"
grep -Fq 'ghcr_retention.py prior-evidence' "$workflow" \
  || fail "latest successful artifact evidence is not selected"
grep -Fq -- '--expected-prior ghcr-expected-prior.json' "$workflow" \
  || fail "planner does not bind evidence to the latest selected run"
grep -Fq -- '--prior-evidence ghcr-prior-evidence.json' "$workflow" \
  || fail "durable prior evidence is not consumed"
grep -Fq "ghcr-retention-plan-\${{ github.run_id }}-\${{ github.run_attempt }}" "$workflow" \
  || fail "artifact identity is not bound to run id and attempt"
grep -Fq 'ghcr_retention.py preview' "$workflow" \
  || fail "held deletion preview is missing"
grep -Fq 'deletion_authorized' "$workflow" \
  || fail "preview does not state deletion authorization"
grep -Fq "ghcr-retention-preview-\${{ github.run_id }}-\${{ github.run_attempt }}" "$workflow" \
  || fail "preview artifact identity is not bound to run id and attempt"

plan_step="$(sed -n '/- name: Build fail-closed retention plan/,/- name: Upload auditable dry-run plan/p' "$workflow")"
if grep -Fq 'GH_TOKEN' <<<"$plan_step"; then
  fail "registry inspection step inherits GH_TOKEN"
fi

for forbidden in \
  'actions: write' \
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
