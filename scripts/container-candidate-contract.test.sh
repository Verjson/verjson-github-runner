#!/usr/bin/env bash
# GENERATED FILE — do not edit by hand.
# Contract: 4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
caller="$root/.github/workflows/container-candidate.yml"
validator="$root/scripts/container_release_manifest.py"
fail() { echo "container candidate contract: $*" >&2; exit 1; }
[ -f "$caller" ] || fail "generated caller is missing"
[ -f "$validator" ] || fail "generated validator is missing"
grep -qx '# Contract: 4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9' "$caller" || fail "caller contract pin differs"
grep -qx '# Contract: 4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9' "$validator" || fail "validator contract pin differs"
grep -q 'uses: Verjson/.github/.github/workflows/container-candidate.yml@4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9' "$caller" || fail "caller does not use the pinned reusable workflow"
grep -q 'contract-ref: 4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9' "$caller" || fail "caller does not pass the shared pin"
grep -q 'acquisition-sha256: 198f7ddd7e628b678f6225c9f22039c5bfc49c1599d9ca169cc15130a3001ab0' "$caller" || fail "caller does not pin the acquisition implementation digest"
[ "$(sha256sum "$caller" | cut -d' ' -f1)" = "5315b57ba4301a91249579b30017d9537cc4fd605e6eb288ba43bd412587a9e9" ] || fail "generated caller was edited"
[ "$(sha256sum "$validator" | cut -d' ' -f1)" = "8d3e5a49a682d9e36dc9e717ce2273a4ad73127ac019c9d3b5757eea2023f847" ] || fail "generated validator was edited"
grep -q '^  pull_request:' "$caller" || fail "pull requests must exercise the build-only path"
if grep -Eq 'secrets: inherit|registry-namespace:|environment:' "$caller"; then
  fail "caller may not inherit credentials or inject registry namespaces or environments"
fi
grep -qF 'NODE_AUTH_TOKEN: ${{ secrets.NODE_AUTH_TOKEN }}' "$caller"   || fail "caller does not pass only the private-package acquisition token"
python3 "$validator" --help >/dev/null
echo "container candidate generated contract passed"
