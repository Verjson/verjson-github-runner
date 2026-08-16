#!/usr/bin/env bash
# GENERATED FILE — do not edit by hand.
# Contract: e12974b8070030b149ca23edfbf751fe4720b50d
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
caller="$root/.github/workflows/container-candidate.yml"
validator="$root/scripts/container_release_manifest.py"
fail() { echo "container candidate contract: $*" >&2; exit 1; }
[ -f "$caller" ] || fail "generated caller is missing"
[ -f "$validator" ] || fail "generated validator is missing"
grep -qx '# Contract: e12974b8070030b149ca23edfbf751fe4720b50d' "$caller" || fail "caller contract pin differs"
grep -qx '# Contract: e12974b8070030b149ca23edfbf751fe4720b50d' "$validator" || fail "validator contract pin differs"
grep -q 'uses: Verjson/.github/.github/workflows/container-candidate.yml@e12974b8070030b149ca23edfbf751fe4720b50d' "$caller" || fail "caller does not use the pinned reusable workflow"
grep -q 'contract-ref: e12974b8070030b149ca23edfbf751fe4720b50d' "$caller" || fail "caller does not pass the shared pin"
grep -q 'acquisition-sha256: 198f7ddd7e628b678f6225c9f22039c5bfc49c1599d9ca169cc15130a3001ab0' "$caller" || fail "caller does not pin the acquisition implementation digest"
grep -q '^  attestations: write$' "$caller" || fail "caller cannot publish signed attestations"
[ "$(sha256sum "$caller" | cut -d' ' -f1)" = "5ee096143ea9e5f493e0a6e64755ccf4d6a81b0fbbf492050a48eda35b4d5070" ] || fail "generated caller was edited"
[ "$(sha256sum "$validator" | cut -d' ' -f1)" = "ab217a262f920891a762988b80105a32642c7c2a731ccbf28729a43c4ad86b89" ] || fail "generated validator was edited"
grep -q '^  pull_request:' "$caller" || fail "pull requests must exercise the build-only path"
if grep -Eq 'secrets: inherit|registry-namespace:|environment:' "$caller"; then
  fail "caller may not inherit credentials or inject registry namespaces or environments"
fi
grep -qF 'NODE_AUTH_TOKEN: ${{ secrets.NODE_AUTH_TOKEN }}' "$caller"   || fail "caller does not pass only the private-package acquisition token"
python3 "$validator" --help >/dev/null
echo "container candidate generated contract passed"
