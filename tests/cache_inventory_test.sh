#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/scripts/cache-inventory.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  echo "cache-inventory test: $*" >&2
  exit 1
}

[[ -x "${script}" ]] || fail "inventory script is missing or not executable"

mkdir -p "${tmp}/bin"
cat >"${tmp}/bin/gh" <<'GH'
#!/usr/bin/env bash
[[ "$*" == "api -X GET --paginate repos/Verjson/example/actions/caches -f per_page=100" ]] || {
  echo "unexpected gh call: $*" >&2
  exit 64
}
printf '%s\n' \
  '{"actions_caches":[{"id":1,"ref":"refs/heads/main","size_in_bytes":6400000000},{"id":2,"ref":"refs/pull/120/merge","size_in_bytes":4200000000}]}' \
  '{"actions_caches":[{"id":3,"ref":"refs/pull/121/merge","size_in_bytes":30000000}]}'
GH
chmod +x "${tmp}/bin/gh"

output="$(PATH="${tmp}/bin:${PATH}" "${script}" Verjson/example)"

grep -qF $'TOTAL\t10630000000\t10.63 GB\t3' <<<"${output}" \
  || fail "total inventory does not aggregate every API page"
grep -qF $'refs/heads/main\t6400000000\t6.40 GB\t1' <<<"${output}" \
  || fail "main cache total is wrong"
grep -qF $'refs/pull/120/merge\t4200000000\t4.20 GB\t1' <<<"${output}" \
  || fail "pull-request cache total is wrong"

if grep -qE 'DELETE|--method DELETE|-X DELETE' "${script}"; then
  fail "read-only inventory script contains a cache deletion path"
fi

echo "cache inventory tests passed"
