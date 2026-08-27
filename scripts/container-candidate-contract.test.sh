#!/usr/bin/env bash
# GENERATED FILE — do not edit by hand.
# Contract: 15d9b9927fb7d6e0efd7a8701a28d795d4b9f151
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
caller="$root/.github/workflows/container-candidate.yml"
validator="$root/scripts/container_release_manifest.py"
fail() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$caller" ] || fail "generated caller is missing"
[ -f "$validator" ] || fail "generated validator is missing"
grep -qx '# Contract: 15d9b9927fb7d6e0efd7a8701a28d795d4b9f151' "$caller" || fail "caller contract pin differs"
grep -qx '# Contract: 15d9b9927fb7d6e0efd7a8701a28d795d4b9f151' "$validator" || fail "validator contract pin differs"
[ "$(grep -c 'uses: Verjson/.github/.github/workflows/container-candidate.yml@15d9b9927fb7d6e0efd7a8701a28d795d4b9f151' "$caller")" -eq 1 ] || fail "validation does not use the pinned read-only reusable workflow"
[ "$(grep -c 'uses: Verjson/.github/.github/workflows/container-candidate-publish.yml@15d9b9927fb7d6e0efd7a8701a28d795d4b9f151' "$caller")" -eq 1 ] || fail "publication does not use the pinned publication reusable workflow"
[ "$(grep -c 'contract-ref: 15d9b9927fb7d6e0efd7a8701a28d795d4b9f151' "$caller")" -eq 2 ] || fail "caller does not pass the shared pin to both event paths"
[ "$(grep -c 'acquisition-sha256: 942b5d55cc441cd54ae11a71b85c5538ce8d091092ef32f3950aad0ca0078ef8' "$caller")" -eq 2 ] || fail "caller does not pin the acquisition implementation digest for both event paths"
[ "$(grep -c 'retry-sha256: 4a11c930f31cc9a07c3b5236511c3545a215c60ba93657e7bc473f7c2ad8fa62' "$caller")" -eq 2 ] || fail "both event paths do not pin the retry verifier digest"
[ "$(grep -c '^      actions: read$' "$caller")" -eq 2 ] || fail "both event paths require Actions reads"
[ "$(grep -c '^      contents: read$' "$caller")" -eq 2 ] || fail "both event paths require source reads"
[ "$(grep -c '^      attestations: write$' "$caller")" -eq 1 ] || fail "only publication may write attestations"
[ "$(grep -c '^      packages: write$' "$caller")" -eq 1 ] || fail "only publication may write candidate images"
[ "$(grep -c '^      id-token: write$' "$caller")" -eq 1 ] || fail "only publication may mint attestation identity"
grep -q "if: github.event_name == 'pull_request'" "$caller" || fail "validation is not restricted to pull requests"
grep -q "if: github.event_name == 'push' && github.ref == 'refs/heads/main'" "$caller" || fail "publication is not restricted to trusted main pushes"
[ "$(sha256sum "$caller" | cut -d' ' -f1)" = "262f01cc9e5a61ab77cc356d9339949383e2852910d5ed77793675ee2f24932f" ] || fail "generated caller was edited"
[ "$(sha256sum "$validator" | cut -d' ' -f1)" = "11d65f576a1adc0cc9b673005cdec1f703a3a0a57525bb46c072018a24b580d1" ] || fail "generated validator was edited"
if grep -Eq 'secrets: inherit|registry-namespace:|environment:' "$caller"; then
  fail "caller may not inherit credentials or inject registry namespaces or environments"
fi
if [ "false" = true ]; then
  [ "$(grep -cF 'NODE_AUTH_TOKEN: ${{ secrets.NODE_AUTH_TOKEN }}' "$caller")" -eq 2 ] || fail "private-package caller does not route its acquisition token to both event paths"
  grep -q '^      packages: read$' "$caller" || fail "private-package validation cannot read approved packages"
else
  ! grep -q 'NODE_AUTH_TOKEN\|packages: read' "$caller" || fail "public-only caller exposes package credentials or read authority"
fi
python3 "$validator" --help >/dev/null
echo "container candidate generated contract passed"
