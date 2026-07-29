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
unset GITHUB_PAT
export RUNNER_TOKEN_CMD="printf integration-placeholder"
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

# Deliver a real signal while docker run is attached to a live job. The
# supervisor trap must stop and remove the child promptly.
export RUNNER_NAME="shutdown-test"
export RUNNER_EPHEMERAL_MAX_JOBS=0
(
  # shellcheck source=../entrypoint.sh
  source "${root}/entrypoint.sh"
  supervise_ephemeral
) >/tmp/gha-ephemeral-shutdown-test.log 2>&1 &
supervisor_pid=$!
for _ in $(seq 1 30); do
  if docker container inspect gha-shutdown-test-job >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
docker container inspect gha-shutdown-test-job >/dev/null
kill -TERM "${supervisor_pid}"
supervisor_status=0
if wait "${supervisor_pid}"; then
  supervisor_status=0
else
  supervisor_status=$?
fi
expected_sigterm_status=0
if [[ "${supervisor_status}" -ne "${expected_sigterm_status}" ]]; then
  echo "signalled supervisor exited with unexpected status ${supervisor_status} (expected ${expected_sigterm_status})" >&2
  exit 1
fi
for _ in $(seq 1 10); do
  if ! docker container inspect gha-shutdown-test-job >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if docker container inspect gha-shutdown-test-job >/dev/null 2>&1; then
  echo "signalled supervisor left its active child running" >&2
  exit 1
fi

echo "Ephemeral supervisor integration passed: fresh layers and signal cleanup."
