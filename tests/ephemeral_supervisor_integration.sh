#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="gha-ephemeral-layer-test:local"

docker build -q -t "${image}" "${root}/tests/fixtures/ephemeral-layer" >/dev/null
cleanup() {
  docker image rm -f "${image}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

export GITHUB_URL="https://github.com/Verjson/test"
export GITHUB_PAT="integration-placeholder"
export RUNNER_NAME="layer-test"
export RUNNER_LABELS="self-hosted,isolated"
export RUNNER_GROUP="isolated"
export RUNNER_WORKDIR="_work"
export RUNNER_IMAGE="${image}"
export RUNNER_EPHEMERAL=true
export RUNNER_EPHEMERAL_MAX_JOBS=2

output="$(
  # shellcheck source=../entrypoint.sh
  source "${root}/entrypoint.sh"
  supervise_ephemeral
)"

[ "$(grep -c 'fresh writable layer' <<< "${output}")" -eq 2 ]
grep -qF 'generation 1' <<< "${output}"
grep -qF 'generation 2' <<< "${output}"
if docker container inspect gha-layer-test-job >/dev/null 2>&1; then
  echo "ephemeral child still exists after the supervisor returned" >&2
  exit 1
fi
echo "Ephemeral supervisor integration passed: two jobs, two fresh writable layers."
