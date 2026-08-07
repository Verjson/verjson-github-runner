#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${root}/scripts/changelog-tool-cache.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

fail() {
  echo "changelog-tool-cache test: $*" >&2
  exit 1
}

reset_cache() {
  if [[ -e "${cache:-}" ]]; then
    chmod -R u+w "${cache}"
    rm -rf "${cache}"
  fi
}

make_curl_mock() {
  mkdir -p "${tmp}/bin"
  cat >"${tmp}/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
output=
previous=
for argument in "$@"; do
  [[ "${previous}" == "-o" ]] && output="${argument}"
  previous="${argument}"
done
[[ -n "${output}" ]]
case "$*" in
  *aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa*) printf 'first contract\n' >"${output}" ;;
  *bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb*) printf 'second contract\n' >"${output}" ;;
  *) exit 22 ;;
esac
CURL
  chmod +x "${tmp}/bin/curl"
}

digest() {
  printf '%s\n' "$1" | sha256sum | cut -d' ' -f1
}

manifest="${tmp}/manifest"
cache="${tmp}/cache"
first_ref=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
second_ref=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
first_digest="$(digest "first contract")"
second_digest="$(digest "second contract")"

printf '%s %s\n%s %s\n' \
  "${first_ref}" "${first_digest}" \
  "${second_ref}" "${second_digest}" >"${manifest}"
make_curl_mock

PATH="${tmp}/bin:${PATH}" "${script}" install "${manifest}" "${cache}"
"${script}" verify "${manifest}" "${cache}"
[[ "$(cat "${cache}/${first_ref}/changelog.py")" == "first contract" ]] \
  || fail "first manifest entry was not installed"
[[ "$(cat "${cache}/${second_ref}/changelog.py")" == "second contract" ]] \
  || fail "additional supported pin was not installed"
[[ "$(stat -c '%a' "${cache}")" == "555" ]] \
  || fail "installed cache root is writable"
[[ "$(stat -c '%a' "${cache}/${first_ref}/changelog.py")" == "444" ]] \
  || fail "installed contract is writable"

chmod 0644 "${cache}/${first_ref}/changelog.py"
printf 'poisoned\n' >"${cache}/${first_ref}/changelog.py"
if "${script}" verify "${manifest}" "${cache}" >/dev/null 2>&1; then
  fail "verification accepted mismatched cached contents"
fi

failure_manifest="${tmp}/failure-manifest"
printf '%s %s\n' "${first_ref}" "${second_digest}" >"${failure_manifest}"
reset_cache
if PATH="${tmp}/bin:${PATH}" \
  "${script}" install "${failure_manifest}" "${cache}" >/dev/null 2>&1; then
  fail "installer accepted a download with the wrong digest"
fi
[[ ! -e "${cache}/${first_ref}/changelog.py" ]] \
  || fail "digest mismatch published unverified contents"

reset_cache
cat >"${tmp}/bin/curl" <<'CURL'
#!/usr/bin/env bash
exit 22
CURL
chmod +x "${tmp}/bin/curl"
if PATH="${tmp}/bin:${PATH}" \
  "${script}" install "${manifest}" "${cache}" >/dev/null 2>&1; then
  fail "installer ignored download failure"
fi

echo "changelog-tool-cache tests passed"
