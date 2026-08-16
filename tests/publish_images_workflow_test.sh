#!/usr/bin/env bash
# shellcheck disable=SC2016 # GitHub expressions below are intentional literals.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${1:-${root}/.github/workflows/publish-images.yml}"

fail() {
  echo "publish-images workflow contract: $*" >&2
  exit 1
}

assert_count() {
  local expected="$1"
  local needle="$2"
  local actual

  actual="$(grep -Fc -- "${needle}" "${workflow}" || true)"
  [[ "${actual}" == "${expected}" ]] \
    || fail "expected ${expected} occurrence(s) of '${needle}', found ${actual}"
}

[[ -f "${workflow}" ]] || fail "workflow not found: ${workflow}"
workflow_text="$(<"${workflow}")"

triggers="$(awk '
  /^on:$/ { capture = 1; next }
  capture && /^[^ ]/ { exit }
  capture { print }
' "${workflow}")"
expected_triggers=$'  push:\n    branches: [main]'
[[ "${triggers}" == "${expected_triggers}" ]] \
  || fail "publication must run only for pushes to main"
assert_count 0 'refs/tags/'

permissions="$(awk '
  /^permissions:$/ { capture = 1; next }
  capture && /^[^ ]/ { exit }
  capture && /^  [a-z][a-z-]*: / { print }
' "${workflow}")"
expected_permissions=$'  contents: read\n  packages: write\n  attestations: write\n  id-token: write'
[[ "${permissions}" == "${expected_permissions}" ]] \
  || fail "top-level permissions must be the exact least-privilege publication set"

while IFS= read -r action; do
  [[ "${action}" =~ ^actions/[A-Za-z0-9_.-]+@[0-9a-f]{40}$ ]] \
    || fail "official action is not pinned to an immutable SHA: ${action}"
done < <(
  awk '/uses: actions\// {
    sub(/^.*uses: /, "")
    sub(/[[:space:]]+#.*$/, "")
    print
  }' "${workflow}"
)

attestation_action='actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2'
base_attestation=$'      - name: Attest base image provenance\n        uses: actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2\n        with:\n          subject-name: ${{ env.IMAGE }}\n          subject-digest: ${{ steps.build.outputs.digest }}\n          push-to-registry: true\n          create-storage-record: false'
kind_attestation=$'      - name: Attest kind image provenance\n        uses: actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2\n        with:\n          subject-name: ${{ env.IMAGE }}\n          subject-digest: ${{ steps.build.outputs.digest }}\n          push-to-registry: true\n          create-storage-record: false'
[[ "${workflow_text}" == *"${base_attestation}"* ]] \
  || fail "base publication does not attest its build digest with the required inputs"
[[ "${workflow_text}" == *"${kind_attestation}"* ]] \
  || fail "kind publication does not attest each matrix build digest with the required inputs"

assert_count 2 "uses: ${attestation_action}"
assert_count 1 'name: Attest base image provenance'
assert_count 1 'name: Attest kind image provenance'
assert_count 2 'subject-name: ${{ env.IMAGE }}'
assert_count 2 'subject-digest: ${{ steps.build.outputs.digest }}'
assert_count 2 'push-to-registry: true'
assert_count 2 'create-storage-record: false'

# BuildKit attestations and immutable digest receipts are independent evidence and
# must remain alongside GitHub artifact attestations.
# BuildKit keys its gha cache index on the scope alone, so the six builds here shared one
# index and overwrote each other's. One scope per image keeps each one stable, and these
# are the scopes image-build-check.yml reads from its base branch.
assert_count 1 'cache-from: type=gha,scope=base'
assert_count 1 'cache-to: type=gha,mode=max,scope=base'
assert_count 1 'cache-from: type=gha,scope=${{ matrix.kind }}'
assert_count 1 'cache-to: type=gha,mode=min,scope=${{ matrix.kind }}'

assert_count 2 'sbom: true'
assert_count 2 'provenance: mode=max'
assert_count 1 'name: Record immutable base image digest'
assert_count 1 'name: Record immutable kind image digest'
assert_count 2 'uses: actions/upload-artifact@'
