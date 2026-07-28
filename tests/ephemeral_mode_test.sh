#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/entrypoint.sh"

assert_status() {
  local expected="$1"
  shift

  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  if [[ "${actual}" -ne "${expected}" ]]; then
    printf 'expected status %s, got %s: %s\n' "${expected}" "${actual}" "$*" >&2
    exit 1
  fi
}

for value in 1 true TRUE True; do
  RUNNER_EPHEMERAL="${value}"
  assert_status 0 runner_ephemeral_enabled
done

for value in "" 0 false FALSE False; do
  RUNNER_EPHEMERAL="${value}"
  assert_status 1 runner_ephemeral_enabled
done

for value in yes on 2 garbage; do
  RUNNER_EPHEMERAL="${value}"
  set +e
  output="$(parse_runner_ephemeral 2>&1)"
  status=$?
  set -e
  [[ "${status}" -ne 0 ]] || {
    printf 'invalid RUNNER_EPHEMERAL=%s unexpectedly succeeded\n' "${value}" >&2
    exit 1
  }
  [[ "${output}" == *"RUNNER_EPHEMERAL must be one of: 1, true, 0, false, or empty"* ]] || {
    printf 'invalid RUNNER_EPHEMERAL=%s did not explain the accepted values\n' "${value}" >&2
    exit 1
  }
done

printf 'ephemeral mode parsing tests passed\n'
