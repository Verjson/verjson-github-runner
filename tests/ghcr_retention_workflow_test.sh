#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$root/.github/workflows/ghcr-retention.yml"

fail() {
  echo "ghcr retention workflow contract: $*" >&2
  exit 1
}

grep -Fq -- "- cron: '23 6 * * 1'" "$workflow" || fail "weekly dry-run schedule is missing"
grep -Fq "if: github.event_name == 'workflow_dispatch' && inputs.mode == 'delete'" "$workflow" \
  || fail "deletion is not restricted to an explicit manual dispatch"
grep -Fq 'environment: ghcr-retention-deletion' "$workflow" \
  || fail "deletion does not use the protected approval environment"
grep -Fq "GHCR_RETENTION_DELETE_ENABLED" "$workflow" \
  || fail "deletion does not require the repository policy switch"
grep -Fq "DELETE ghcr.io/verjson/gha-runner" "$workflow" \
  || fail "deletion does not require exact package confirmation"
grep -Fq -- '--confirm-plan-sha256 "$PLAN_SHA256"' "$workflow" \
  || fail "apply does not bind deletion to the dry-run plan"
grep -Fq 'GHCR_PROTECTED_DIGESTS: ${{ vars.GHCR_PROTECTED_DIGESTS }}' "$workflow" \
  || fail "deployment digest inventory is not supplied to both stages"
[[ "$(grep -Fc 'GHCR_PROTECTED_DIGESTS: ${{ vars.GHCR_PROTECTED_DIGESTS }}' "$workflow")" == 2 ]] \
  || fail "plan and apply do not use the same deployment digest inventory"

delete_job="$(awk '/^  delete:/{capture=1} capture{print}' "$workflow")"
grep -Fq 'packages: write' <<<"$delete_job" || fail "delete job lacks package write permission"
plan_job="$(awk '/^  plan:/{capture=1} /^  delete:/{capture=0} capture{print}' "$workflow")"
if grep -Fq 'packages: write' <<<"$plan_job"; then
  fail "dry-run plan has package write permission"
fi

while IFS= read -r action; do
  [[ "$action" =~ @[0-9a-f]{40}$ ]] || fail "action is not pinned to an immutable SHA: $action"
done < <(sed -n 's/^[[:space:]]*- uses: \([^[:space:]#]*\).*/\1/p' "$workflow")

echo "ghcr retention workflow contract passed"
