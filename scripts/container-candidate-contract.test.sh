#!/usr/bin/env bash
# GENERATED FILE — do not edit by hand.
# Contract: bced83b95e17c65ed4500c83756e2638f7dbb9d4
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
caller="$root/.github/workflows/container-candidate.yml"
validator="$root/scripts/container_release_manifest.py"
fail() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$caller" ] || fail "generated caller is missing"
[ -f "$validator" ] || fail "generated validator is missing"
grep -qx '# Contract: bced83b95e17c65ed4500c83756e2638f7dbb9d4' "$caller" || fail "caller contract pin differs"
grep -qx '# Contract: bced83b95e17c65ed4500c83756e2638f7dbb9d4' "$validator" || fail "validator contract pin differs"
[ "$(grep -c 'uses: Verjson/.github/.github/workflows/container-candidate.yml@bced83b95e17c65ed4500c83756e2638f7dbb9d4' "$caller")" -eq 2 ] || fail "caller does not use the pinned reusable workflow for both event paths"
[ "$(grep -c 'contract-ref: bced83b95e17c65ed4500c83756e2638f7dbb9d4' "$caller")" -eq 2 ] || fail "caller does not pass the shared pin to both event paths"
[ "$(grep -c 'acquisition-sha256: 198f7ddd7e628b678f6225c9f22039c5bfc49c1599d9ca169cc15130a3001ab0' "$caller")" -eq 2 ] || fail "caller does not pin the acquisition implementation digest for both event paths"
[ "$(grep -c '^      actions: read$' "$caller")" -eq 2 ] || fail "both event paths require Actions reads"
[ "$(grep -c '^      contents: read$' "$caller")" -eq 2 ] || fail "both event paths require source reads"
[ "$(grep -c '^      attestations: write$' "$caller")" -eq 1 ] || fail "only publication may write attestations"
[ "$(grep -c '^      packages: write$' "$caller")" -eq 1 ] || fail "only publication may write candidate images"
[ "$(grep -c '^      id-token: write$' "$caller")" -eq 1 ] || fail "only publication may mint attestation identity"
grep -q "if: github.event_name == 'pull_request'" "$caller" || fail "validation is not restricted to pull requests"
grep -q "if: github.event_name == 'push' && github.ref == 'refs/heads/main'" "$caller" || fail "publication is not restricted to trusted main pushes"
[ "$(sha256sum "$caller" | cut -d' ' -f1)" = "80023c47766b51a8b3fc4e09a3ad103f781da4915d53b354857f31a1c0c79b6e" ] || fail "generated caller was edited"
[ "$(sha256sum "$validator" | cut -d' ' -f1)" = "0fba02df279d4a4a7f68ed8f6581837fe0721e2a062bc60962f8865527025979" ] || fail "generated validator was edited"
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
