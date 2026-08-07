#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 install|verify MANIFEST CACHE_ROOT" >&2
  exit 64
}

fail() {
  echo "changelog tool cache: $*" >&2
  exit 1
}

digest() {
  sha256sum "$1" | cut -d' ' -f1
}

validate_entry() {
  local ref="$1"
  local expected="$2"

  [[ "${ref}" =~ ^[0-9a-f]{40}$ ]] \
    || fail "invalid contract commit in manifest: ${ref}"
  [[ "${expected}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "invalid SHA-256 for ${ref}: ${expected}"
}

install_entry() {
  local ref="$1"
  local expected="$2"
  local cache_dir="${cache_root}/${ref}"
  local contract="${cache_dir}/changelog.py"
  local temporary

  install -d -m 0755 "${cache_dir}"
  temporary="$(mktemp "${cache_dir}/.changelog.XXXXXX")"
  if ! curl -fsSL \
    "https://raw.githubusercontent.com/Verjson/.github/${ref}/scripts/changelog.py" \
    -o "${temporary}"; then
    rm -f "${temporary}"
    fail "cannot download changelog contract at ${ref}"
  fi
  if [[ "$(digest "${temporary}")" != "${expected}" ]]; then
    rm -f "${temporary}"
    fail "downloaded changelog contract at ${ref} does not match ${expected}"
  fi
  install -m 0444 "${temporary}" "${contract}"
  rm -f "${temporary}"
  chmod 0555 "${cache_dir}"
}

verify_entry() {
  local ref="$1"
  local expected="$2"
  local cache_dir="${cache_root}/${ref}"
  local contract="${cache_dir}/changelog.py"

  [[ -f "${contract}" ]] \
    || fail "missing cached changelog contract at ${contract}"
  [[ "$(digest "${contract}")" == "${expected}" ]] \
    || fail "cached changelog contract at ${contract} does not match ${expected}"
  [[ "$(stat -c '%a' "${cache_root}")" == "555" ]] \
    || fail "cache root ${cache_root} is not read-only"
  [[ "$(stat -c '%a' "${cache_dir}")" == "555" ]] \
    || fail "cache directory ${cache_dir} is not read-only"
  [[ "$(stat -c '%a' "${contract}")" == "444" ]] \
    || fail "cached contract ${contract} is not read-only"
}

[[ "$#" == 3 ]] || usage
mode="$1"
manifest="$2"
cache_root="$3"
[[ "${mode}" == "install" || "${mode}" == "verify" ]] || usage
[[ -f "${manifest}" ]] || fail "manifest does not exist: ${manifest}"

entry_count=0
while read -r ref expected remainder; do
  [[ -z "${ref}" || "${ref}" == \#* ]] && continue
  [[ -z "${remainder:-}" ]] || fail "unexpected manifest fields for ${ref}"
  validate_entry "${ref}" "${expected:-}"
  "${mode}_entry" "${ref}" "${expected}"
  entry_count=$((entry_count + 1))
done <"${manifest}"

[[ "${entry_count}" -gt 0 ]] || fail "manifest contains no changelog contracts"

if [[ "${mode}" == "install" ]]; then
  chmod 0555 "${cache_root}"
  "$0" verify "${manifest}" "${cache_root}"
fi
