#!/usr/bin/env bash
set -euo pipefail

# Unit test suite for entrypoint.sh token resolution, URL parsing, and cleanup logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Running entrypoint.sh unit tests..."

# Create temporary test sandbox directory
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cd "${TMP_DIR}"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ ${msg}"
    touch "${TMP_DIR}/passed_$(date +%s%N)_$RANDOM"
  else
    echo "  ✗ ${msg} (expected '${expected}', got '${actual}')"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  if [[ "$haystack" == *"${needle}"* ]]; then
    echo "  ✓ ${msg}"
    touch "${TMP_DIR}/passed_$(date +%s%N)_$RANDOM"
  else
    echo "  ✗ ${msg} (expected substring '${needle}' in '${haystack}')"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  fi
}

assert_not_contains() {
  local needle="$1"
  local haystack="$2"
  local msg="$3"
  if [[ "$haystack" != *"${needle}"* ]]; then
    echo "  ✓ ${msg}"
    touch "${TMP_DIR}/passed_$(date +%s%N)_$RANDOM"
  else
    echo "  ✗ ${msg} (unexpected substring '${needle}' in '${haystack}')"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="$2"
  if [[ -e "${path}" ]]; then
    echo "  ✓ ${msg}"
    touch "${TMP_DIR}/passed_$(date +%s%N)_$RANDOM"
  else
    echo "  ✗ ${msg} (expected '${path}' to exist)"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  fi
}

assert_file_absent() {
  local path="$1"
  local msg="$2"
  if [[ ! -e "${path}" ]]; then
    echo "  ✓ ${msg}"
    touch "${TMP_DIR}/passed_$(date +%s%N)_$RANDOM"
  else
    echo "  ✗ ${msg} (expected '${path}' to be absent)"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  fi
}

mock_passing_ci_tools() {
  gh() { echo "gh $*" >> "${command_log}"; }
  docker() { echo "docker $*" >> "${command_log}"; }
  node() {
    echo "node $*" >> "${command_log}"
    echo "v24.18.0"
  }
  npm() { echo "npm $*" >> "${command_log}"; }
  jq() {
    echo "jq $*" >> "${command_log}"
    echo "jq-1.7"
  }
  git() { echo "git $*" >> "${command_log}"; }
  bash() {
    echo "bash $*" >> "${command_log}"
    echo "GNU bash, version 5.2.15(1)-release"
  }
  curl() { echo "curl $*" >> "${command_log}"; }
  grep() { echo "grep $*" >> "${command_log}"; }
  sed() { echo "sed $*" >> "${command_log}"; }
  awk() { echo "awk $*" >> "${command_log}"; }
  find() { echo "find $*" >> "${command_log}"; }
  base64() { echo "base64 $*" >> "${command_log}"; }
  tar() { echo "tar $*" >> "${command_log}"; }
  gzip() { echo "gzip $*" >> "${command_log}"; }
  unzip() { echo "unzip $*" >> "${command_log}"; }
  python3() {
    echo "python3 $*" >> "${command_log}"
    [[ "${1:-}" == "--version" ]] && echo "Python 3.13.5"
    return 0
  }
  shellcheck() { echo "shellcheck $*" >> "${command_log}"; }
  cmp() { echo "cmp $*" >> "${command_log}"; }
  diff() { echo "diff $*" >> "${command_log}"; }
  zstd() { echo "zstd $*" >> "${command_log}"; }
  cc() { echo "cc $*" >> "${command_log}"; }
  make() { echo "make $*" >> "${command_log}"; }
  pkg-config() { echo "pkg-config $*" >> "${command_log}"; }
  changelog-tool-cache() { echo "changelog-tool-cache $*" >> "${command_log}"; }
  # Deterministic regardless of whether the machine running the suite has a compiler.
  PATH="$(cxx_stub_dir):${PATH}"
}

# `c++`/`g++` are not shadowable by a shell function, so the C++ admission check resolves
# them on PATH. These helpers move PATH rather than mocking a command.
cxx_stub_dir() {
  local dir="${TMP_DIR}/cxx_stub"
  mkdir -p "${dir}"
  printf '#!/bin/sh\nexit 0\n' > "${dir}/c++"
  chmod +x "${dir}/c++"
  echo "${dir}"
}

expected_ci_admission_commands() {
  printf '%s' $'gh --version\ndocker version\ndocker compose version\ndocker buildx version\nnode --version\nnpm --version\njq --version\ngit --version\nbash --version\ncurl --version\ngrep --version\nsed --version\nawk --version\nfind --version\nbase64 --version\ntar --version\ngzip --version\nunzip -v\npython3 --version\npython3 -c import yaml\nshellcheck --version\ncmp /dev/null /dev/null\ndiff /dev/null /dev/null\nzstd --version\ncc --version\nmake --version\npkg-config --version\nchangelog-tool-cache verify /usr/local/share/verjson-changelog-tools.manifest /opt/verjson/changelog-tools'
}

# Mock api_base for tests
api_base="https://api.github.com/repos/Verjson/test/actions/runners"

# -----------------------------------------------------------------------------
# Test 1: resolve_token with GITHUB_PAT
# -----------------------------------------------------------------------------
echo "Test 1: resolve_token with GITHUB_PAT"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_TOKEN || true
  GITHUB_PAT="dummy_pat"
  get_token() { echo "mock_pat_token"; }
  resolve_token
  assert_eq "mock_pat_token" "${RUNNER_TOKEN}" "Resolves token via GITHUB_PAT"
)

# -----------------------------------------------------------------------------
# Test 2: resolve_token with RUNNER_TOKEN_CMD
# -----------------------------------------------------------------------------
echo "Test 2: resolve_token with RUNNER_TOKEN_CMD"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_TOKEN || true
  RUNNER_TOKEN_CMD="echo mock_cmd_token"
  resolve_token
  assert_eq "mock_cmd_token" "${RUNNER_TOKEN}" "Resolves token via RUNNER_TOKEN_CMD"
)

# -----------------------------------------------------------------------------
# Test 3: resolve_token with static RUNNER_TOKEN
# -----------------------------------------------------------------------------
echo "Test 3: resolve_token with static RUNNER_TOKEN"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_TOKEN || true
  RUNNER_TOKEN="mock_static_token"
  resolve_token
  assert_eq "mock_static_token" "${RUNNER_TOKEN}" "Preserves static RUNNER_TOKEN"
)

# -----------------------------------------------------------------------------
# Test 4: resolve_token errors when no token source is supplied
# -----------------------------------------------------------------------------
echo "Test 4: resolve_token fails when no token source is set"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_TOKEN || true
  set +e
  output=$(resolve_token 2>&1)
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    assert_contains "Provide GITHUB_PAT" "${output}" "Fails with helpful error message when token is missing"
  else
    echo "  ✗ Expected failure when no token set, but succeeded"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  fi
)

# -----------------------------------------------------------------------------
# Test 5: cleanup with GITHUB_PAT (success path)
# -----------------------------------------------------------------------------
echo "Test 5: cleanup with GITHUB_PAT success"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_REMOVE_TOKEN_CMD || true
  GITHUB_PAT="dummy_pat"
  get_token() { echo "remove_token_123"; }

  cat << 'EOF' > config.sh
#!/usr/bin/env bash
echo "config.sh called with $@" >> config_calls.log
EOF
  chmod +x config.sh

  (cleanup)
  assert_contains "--token remove_token_123" "$(< config_calls.log)" "Calls config.sh remove with PAT remove token"
)

# -----------------------------------------------------------------------------
# Test 6: cleanup with GITHUB_PAT fallback on API error
# -----------------------------------------------------------------------------
echo "Test 6: cleanup with GITHUB_PAT fallback on API error"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_REMOVE_TOKEN_CMD || true
  GITHUB_PAT="dummy_pat"
  get_token() { return 1; }

  cat << 'EOF' > config.sh
#!/usr/bin/env bash
echo "config.sh called with $@" >> config_calls.log
if [[ "$*" == *"remove --token"* ]]; then
  exit 1
fi
EOF
  chmod +x config.sh

  (cleanup)
  assert_contains "--local" "$(< config_calls.log)" "Falls back to config.sh remove --local when PAT token fetch fails"
)

# -----------------------------------------------------------------------------
# Test 7: cleanup with RUNNER_REMOVE_TOKEN_CMD (success path)
# -----------------------------------------------------------------------------
echo "Test 7: cleanup with RUNNER_REMOVE_TOKEN_CMD success"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_REMOVE_TOKEN_CMD || true
  RUNNER_REMOVE_TOKEN_CMD="echo remove_cmd_tok"

  cat << 'EOF' > config.sh
#!/usr/bin/env bash
echo "config.sh called with $@" >> config_calls.log
EOF
  chmod +x config.sh

  (cleanup)
  assert_contains "--token remove_cmd_tok" "$(< config_calls.log)" "Calls config.sh remove with RUNNER_REMOVE_TOKEN_CMD output"
)

# -----------------------------------------------------------------------------
# Test 8: cleanup with RUNNER_REMOVE_TOKEN_CMD fallback on command failure
# -----------------------------------------------------------------------------
echo "Test 8: cleanup with RUNNER_REMOVE_TOKEN_CMD fallback on command failure"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_REMOVE_TOKEN_CMD || true
  RUNNER_REMOVE_TOKEN_CMD="false"

  cat << 'EOF' > config.sh
#!/usr/bin/env bash
echo "config.sh called with $@" >> config_calls.log
EOF
  chmod +x config.sh

  (cleanup)
  assert_contains "--local" "$(< config_calls.log)" "Falls back to config.sh remove --local when RUNNER_REMOVE_TOKEN_CMD fails"
)

# -----------------------------------------------------------------------------
# Test 9: cleanup default local branch
# -----------------------------------------------------------------------------
echo "Test 9: cleanup default local branch"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset GITHUB_PAT RUNNER_REMOVE_TOKEN_CMD || true

  cat << 'EOF' > config.sh
#!/usr/bin/env bash
echo "config.sh called with $@" >> config_calls.log
EOF
  chmod +x config.sh

  (cleanup)
  assert_contains "remove --local" "$(< config_calls.log)" "Executes local removal by default"
)

# -----------------------------------------------------------------------------
# Test 10: parse_github_url with repo URL
# -----------------------------------------------------------------------------
echo "Test 10: parse_github_url with repo URL"
(
  source "${REPO_ROOT}/entrypoint.sh"
  GITHUB_URL="https://github.com/my-org/my-repo"
  RUNNER_GROUP="custom_group"
  parse_github_url
  assert_eq "https://api.github.com/repos/my-org/my-repo/actions/runners" "${api_base}" "Parses repo API base"
  assert_eq "0" "${#group_arg[@]}" "Omits --runnergroup for repo URL even if RUNNER_GROUP is set"
)

# -----------------------------------------------------------------------------
# Test 11: parse_github_url with org URL and default runner group
# -----------------------------------------------------------------------------
echo "Test 11: parse_github_url with org URL and default runner group"
(
  source "${REPO_ROOT}/entrypoint.sh"
  GITHUB_URL="https://github.com/my-org"
  RUNNER_GROUP="Default"
  parse_github_url
  assert_eq "https://api.github.com/orgs/my-org/actions/runners" "${api_base}" "Parses org API base"
  assert_eq "0" "${#group_arg[@]}" "Omits --runnergroup when group is Default"
)

# -----------------------------------------------------------------------------
# Test 12: parse_github_url with org URL and custom runner group
# -----------------------------------------------------------------------------
echo "Test 12: parse_github_url with org URL and custom runner group"
(
  source "${REPO_ROOT}/entrypoint.sh"
  GITHUB_URL="https://github.com/my-org"
  RUNNER_GROUP="custom_group"
  parse_github_url
  assert_eq "https://api.github.com/orgs/my-org/actions/runners" "${api_base}" "Parses org API base"
  assert_eq "--runnergroup custom_group" "${group_arg[*]}" "Includes --runnergroup for custom org group"
)

# -----------------------------------------------------------------------------
# Test 13: main execution with RUNNER_DIR override and RUNNER_EPHEMERAL=1
# -----------------------------------------------------------------------------
echo "Test 13: main execution with RUNNER_DIR override and RUNNER_EPHEMERAL=1"
(
  TEST_RUNNER_DIR="${TMP_DIR}/test_runner_workdir"
  mkdir -p "${TEST_RUNNER_DIR}"

  cat << 'EOF' > "${TEST_RUNNER_DIR}/config.sh"
#!/usr/bin/env bash
echo "config.sh called with args: $@" >> config_args.log
EOF
  cat << 'EOF' > "${TEST_RUNNER_DIR}/run.sh"
#!/usr/bin/env bash
echo "run.sh executed" >> run_exec.log
if env | grep -Eq '^(RUNNER_TOKEN|GITHUB_PAT|RUNNER_TOKEN_CMD|RUNNER_REMOVE_TOKEN_CMD)='; then
  touch credential_exposed
fi
EOF
  chmod +x "${TEST_RUNNER_DIR}/config.sh" "${TEST_RUNNER_DIR}/run.sh"

  export GITHUB_URL="https://github.com/my-org/my-repo"
  unset GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_REMOVE_TOKEN_CMD || true
  export RUNNER_TOKEN="mock_token"
  export RUNNER_DIR="${TEST_RUNNER_DIR}"
  export RUNNER_EPHEMERAL=1
  export RUNNER_FRESH_CONTAINER=1

  source "${REPO_ROOT}/entrypoint.sh"
  main &
  main_pid=$!
  sleep 1
  kill -TERM $main_pid 2>/dev/null || true
  wait $main_pid 2>/dev/null || true

  assert_contains "--ephemeral" "$(< "${TEST_RUNNER_DIR}/config_args.log")" "Passes --ephemeral flag when RUNNER_EPHEMERAL is set"
  assert_contains "run.sh executed" "$(< "${TEST_RUNNER_DIR}/run_exec.log")" "Launches run.sh in working directory"
  assert_file_absent "${TEST_RUNNER_DIR}/credential_exposed" "Discards registration credentials before workflow execution"
)

# -----------------------------------------------------------------------------
# Test 14: exact ci label matching
# -----------------------------------------------------------------------------
echo "Test 14: exact ci label matching"
(
  source "${REPO_ROOT}/entrypoint.sh"

  runner_labels_include_ci "self-hosted, ci ,docker"
  assert_eq "0" "$?" "Matches ci as a trimmed comma-separated label"

  runner_labels_include_ci "self-hosted,CI,docker"
  assert_eq "0" "$?" "Matches uppercase CI because GitHub labels are case-insensitive"

  runner_labels_include_ci "self-hosted,Ci,docker"
  assert_eq "0" "$?" "Matches mixed-case Ci because GitHub labels are case-insensitive"

  set +e
  runner_labels_include_ci "self-hosted,circleci,ci-extra"
  status=$?
  set -e
  assert_eq "1" "${status}" "Does not match labels that merely contain ci"
)

# -----------------------------------------------------------------------------
# Test 15: passing ci admission exercises the complete tool contract
# -----------------------------------------------------------------------------
echo "Test 15: passing ci admission exercises the complete tool contract"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_pass.log"
  mock_passing_ci_tools

  attest_ci_runner >/dev/null

  assert_eq "$(expected_ci_admission_commands)" "$(< "${command_log}")" "Exercises every required ci capability"
)

# -----------------------------------------------------------------------------
# Test 16: failing ci admission stops at the failed capability
# -----------------------------------------------------------------------------
echo "Test 16: failing ci admission stops at the failed capability"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_fail.log"
  mock_passing_ci_tools
  docker() {
    echo "docker $*" >> "${command_log}"
    [[ "$*" != "version" ]]
  }

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects ci admission when a required capability fails"
  assert_contains "Docker daemon is unavailable or unhealthy" "${output}" "Identifies the failed capability"
  assert_eq $'gh --version\ndocker version' "$(< "${command_log}")" "Stops admission immediately after failure"
)

# -----------------------------------------------------------------------------
# Test 17: ci admission rejects Node.js below its runtime floor
# -----------------------------------------------------------------------------
echo "Test 17: ci admission rejects Node.js below its runtime floor"
(
  source "${REPO_ROOT}/entrypoint.sh"
  node() { echo "v24.9.9"; }

  set +e
  output="$(run_node_admission_check 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects Node.js below 24.10"
  assert_contains "Node.js >= 24.10 is required" "${output}" "Reports the required Node.js floor"
)

# -----------------------------------------------------------------------------
# Test 18: failed ci admission precedes token minting and registration
# -----------------------------------------------------------------------------
echo "Test 18: failed ci admission precedes token minting and registration"
(
  source "${REPO_ROOT}/entrypoint.sh"
  boundary_dir="${TMP_DIR}/admission_boundary"
  mkdir -p "${boundary_dir}"

  cat << 'EOF' > "${boundary_dir}/config.sh"
#!/usr/bin/env bash
touch config_called
EOF
  cat << 'EOF' > "${boundary_dir}/run.sh"
#!/usr/bin/env bash
touch run_called
EOF
  chmod +x "${boundary_dir}/config.sh" "${boundary_dir}/run.sh"

  GITHUB_URL="https://github.com/my-org"
  GITHUB_PAT="dummy_pat"
  RUNNER_DIR="${boundary_dir}"
  RUNNER_LABELS="self-hosted,CI"
  get_token() {
    touch "${boundary_dir}/token_minted"
    echo "unexpected_token"
  }
  gh() { return 1; }

  set +e
  main >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "1" "${status}" "Main fails closed when ci admission fails"
  assert_file_absent "${boundary_dir}/token_minted" "Does not mint a token after failed admission"
  assert_file_absent "${boundary_dir}/config_called" "Does not register after failed admission"
  assert_file_absent "${boundary_dir}/run_called" "Does not start the runner after failed admission"
)

# -----------------------------------------------------------------------------
# Test 19: a non-ci label is not subject to ci admission
# -----------------------------------------------------------------------------
echo "Test 19: a non-ci label is not subject to ci admission"
(
  source "${REPO_ROOT}/entrypoint.sh"
  non_ci_dir="${TMP_DIR}/non_ci_boundary"
  mkdir -p "${non_ci_dir}"

  cat << 'EOF' > "${non_ci_dir}/config.sh"
#!/usr/bin/env bash
touch config_called
EOF
  cat << 'EOF' > "${non_ci_dir}/run.sh"
#!/usr/bin/env bash
touch run_called
EOF
  chmod +x "${non_ci_dir}/config.sh" "${non_ci_dir}/run.sh"

  GITHUB_URL="https://github.com/my-org"
  GITHUB_PAT="dummy_pat"
  RUNNER_DIR="${non_ci_dir}"
  RUNNER_LABELS="self-hosted,circleci,ci-extra"
  get_token() {
    touch "${non_ci_dir}/token_minted"
    echo "mock_token"
  }
  attest_ci_runner() {
    touch "${non_ci_dir}/unexpected_attestation"
    return 1
  }

  main >/dev/null 2>&1

  assert_file_absent "${non_ci_dir}/unexpected_attestation" "Uses exact matching before requiring ci admission"
  assert_file_exists "${non_ci_dir}/token_minted" "Mints a token for labels outside the ci contract"
  assert_file_exists "${non_ci_dir}/config_called" "Registers labels outside the ci contract"
  assert_file_exists "${non_ci_dir}/run_called" "Starts labels outside the ci contract"
)

# -----------------------------------------------------------------------------
# Test 20: standalone ci dispatches directly to admission
# -----------------------------------------------------------------------------
echo "Test 20: standalone ci dispatches directly to admission"
(
  standalone_dir="${TMP_DIR}/standalone_ci"
  command_log="${standalone_dir}/commands.log"
  mkdir -p "${standalone_dir}"
  : > "${command_log}"
  export command_log

  mock_passing_ci_tools
  export -f gh docker node npm jq git bash curl grep sed awk find base64 tar gzip unzip
  export -f python3 shellcheck cmp diff zstd cc make pkg-config changelog-tool-cache
  export PATH

  cat << EOF > "${standalone_dir}/config.sh"
#!/usr/bin/env bash
touch "${standalone_dir}/config_called"
EOF
  chmod +x "${standalone_dir}/config.sh"

  unset GITHUB_URL GITHUB_PAT RUNNER_TOKEN || true
  export RUNNER_DIR="${standalone_dir}"
  export RUNNER_TOKEN_CMD="touch '${standalone_dir}/token_resolved'; echo unexpected"

  set +e
  output="$("${REPO_ROOT}/entrypoint.sh" ci 2>&1)"
  status=$?
  set -e

  assert_eq "0" "${status}" "Standalone ci exits successfully without registration inputs"
  assert_eq "$(expected_ci_admission_commands)" "$(< "${command_log}")" "Dispatches directly to the complete ci attestation"
  assert_file_absent "${standalone_dir}/token_resolved" "Does not resolve a registration token"
  assert_file_absent "${standalone_dir}/config_called" "Does not invoke config.sh"
  assert_contains "CI runner admission passed." "${output}" "Reports successful standalone admission"
)

# -----------------------------------------------------------------------------
# Test 21: RUNNER_EPHEMERAL is parsed as a real boolean
# -----------------------------------------------------------------------------
echo "Test 21: RUNNER_EPHEMERAL boolean parsing"
(
  source "${REPO_ROOT}/entrypoint.sh"
  for value in 1 true TRUE yes on; do
    RUNNER_EPHEMERAL="${value}"
    normalize_ephemeral_mode
    assert_eq "1" "${RUNNER_EPHEMERAL_ENABLED}" "Accepts true value ${value}"
  done
  for value in '' 0 false FALSE no off; do
    RUNNER_EPHEMERAL="${value}"
    normalize_ephemeral_mode
    assert_eq "0" "${RUNNER_EPHEMERAL_ENABLED}" "Accepts false value '${value}'"
  done
  RUNNER_EPHEMERAL="sometimes"
  set +e
  output="$(normalize_ephemeral_mode 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects an ambiguous ephemeral value"
  assert_contains "must be one of" "${output}" "Explains the accepted boolean values"
)

# -----------------------------------------------------------------------------
# Test 22: supervisor creates a fresh --rm child for every generation
# -----------------------------------------------------------------------------
echo "Test 22: direct ephemeral mode fails closed without fresh-container attestation"
(
  TEST_RUNNER_DIR="${TMP_DIR}/unsafe_ephemeral_runner"
  mkdir -p "${TEST_RUNNER_DIR}"

  cat << 'EOF' > "${TEST_RUNNER_DIR}/config.sh"
#!/usr/bin/env bash
touch config_called
EOF
  chmod +x "${TEST_RUNNER_DIR}/config.sh"

  export GITHUB_URL="https://github.com/Verjson/test"
  export RUNNER_DIR="${TEST_RUNNER_DIR}"
  export RUNNER_EPHEMERAL=1
  export RUNNER_TOKEN_CMD="touch '${TEST_RUNNER_DIR}/token_resolved'; echo unexpected"
  unset RUNNER_FRESH_CONTAINER GITHUB_PAT RUNNER_TOKEN RUNNER_REMOVE_TOKEN_CMD || true

  set +e
  output="$("${REPO_ROOT}/entrypoint.sh" 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects direct ephemeral mode without a fresh disposable container"
  assert_contains "RUNNER_EPHEMERAL requires a fresh disposable container" "${output}" "Explains the required isolation contract"
  assert_file_absent "${TEST_RUNNER_DIR}/token_resolved" "Fails before resolving a registration token"
  assert_file_absent "${TEST_RUNNER_DIR}/config_called" "Fails before runner registration"
)

# -----------------------------------------------------------------------------
# Test 23: supervisor creates a fresh --rm child for every generation
# -----------------------------------------------------------------------------
echo "Test 23: ephemeral supervisor child lifecycle"
(
  source "${REPO_ROOT}/entrypoint.sh"
  docker_log="${TMP_DIR}/supervisor_docker.log"
  token_log="${TMP_DIR}/supervisor_token.log"
  : > "${docker_log}"
  : > "${token_log}"
  docker() {
    printf '%s\n' "$*" >> "${docker_log}"
    if [[ "$*" == container\ inspect* ]]; then
      return 1
    fi
    if [[ "$*" == run\ * ]]; then
      IFS= read -r child_token
      printf '%s\n' "${child_token}" >> "${token_log}"
    fi
    return 0
  }
  mint_count=0
  resolve_token() {
    mint_count=$((mint_count + 1))
    RUNNER_TOKEN="job-token-${mint_count}"
  }
  sleep() { :; }

  GITHUB_URL="https://github.com/Verjson/test"
  GITHUB_PAT="dummy"
  RUNNER_NAME="isolated-1"
  RUNNER_LABELS="self-hosted,isolated"
  RUNNER_GROUP="isolated"
  RUNNER_WORKDIR="_work"
  RUNNER_IMAGE="gha-runner:test"
  RUNNER_EPHEMERAL=true
  RUNNER_EPHEMERAL_MAX_JOBS=2
  # Low enough to admit any host running this suite; the point is that it propagates.
  RUNNER_MIN_MEMORY_MB=1024

  supervise_ephemeral >/dev/null
  run_count="$(grep -c '^run --rm ' "${docker_log}")"
  remove_count="$(grep -c '^rm -f gha-isolated-1-job$' "${docker_log}")"
  assert_eq "2" "${run_count}" "Runs two distinct disposable child generations"
  assert_eq "4" "${remove_count}" "Sweeps the exact child before and after every generation"
  assert_contains "RUNNER_EPHEMERAL=1" "$(< "${docker_log}")" "Marks every child runner one-job ephemeral"
  assert_contains "RUNNER_FRESH_CONTAINER=1" "$(< "${docker_log}")" "Marks the supervisor-created child as a fresh layer"
  assert_contains "job-token-1" "$(< "${token_log}")" "Streams a one-shot token to the first child"
  assert_contains "job-token-2" "$(< "${token_log}")" "Streams a distinct one-shot token to the next child"
  assert_not_contains "job-token-" "$(< "${docker_log}")" "Keeps one-shot tokens out of Docker argv and inspect metadata"
  assert_contains "RUNNER_TOKEN_STDIN=1" "$(< "${docker_log}")" "Uses the non-metadata stdin token channel"
  assert_contains "RUNNER_MIN_MEMORY_MB=1024" "$(< "${docker_log}")" "Gives the child the supervisor's own memory threshold"
  assert_not_contains "GITHUB_PAT=" "$(< "${docker_log}")" "Does not expose the renewable PAT to job children"
  assert_not_contains "RUNNER_TOKEN_CMD=" "$(< "${docker_log}")" "Does not expose the token-mint command to job children"
  assert_not_contains "RUNNER_REMOVE_TOKEN_CMD=" "$(< "${docker_log}")" "Does not expose removal credentials to job children"
  if grep '^run --rm ' "${docker_log}" | grep -q -- '-v /var/run/docker.sock'; then
    echo "  ✗ Default isolated child unexpectedly receives the Docker socket"
    touch "${TMP_DIR}/failed_$(date +%s%N)_$RANDOM"
  else
    echo "  ✓ Default isolated child receives no Docker socket"
    touch "${TMP_DIR}/passed_$(date +%s%N)_$RANDOM"
  fi
)

# -----------------------------------------------------------------------------
# Test 24: isolated-lane contract is admitted and preserved
# -----------------------------------------------------------------------------
echo "Test 24: isolated-lane launch contract"
(
  source "${REPO_ROOT}/entrypoint.sh"
  docker_log="${TMP_DIR}/isolated_docker.log"
  : > "${docker_log}"
  docker() {
    printf '%s\n' "$*" >> "${docker_log}"
    [[ "$*" == container\ inspect* ]] && return 1
    [[ "$*" == run\ * ]] && IFS= read -r _
    return 0
  }
  sleep() { :; }

  GITHUB_URL="https://github.com/Verjson"
  RUNNER_TOKEN_CMD="printf one-shot"
  RUNNER_NAME="isolated-runner-1"
  RUNNER_LABELS="self-hosted,isolated,linux,x64,untrusted-pr,ephemeral,no-host-docker"
  RUNNER_GROUP="isolated-pr"
  RUNNER_IMAGE="ghcr.io/verjson/gha-runner@sha256:$(printf 'a%.0s' {1..64})"
  RUNNER_CHILD_NETWORK="gha-isolated-deny-metadata"
  RUNNER_METADATA_DENY_ATTEST_CMD=":"
  RUNNER_EPHEMERAL=1
  RUNNER_EPHEMERAL_MAX_JOBS=1

  output="$(supervise_ephemeral)"
  assert_contains "--network gha-isolated-deny-metadata" "$(< "${docker_log}")" "Uses the admitted metadata-denying network"
  assert_contains "--add-host metadata.google.internal:127.0.0.1" "$(< "${docker_log}")" "Overrides the metadata hostname in the child only"
  assert_not_contains "/var/run/docker.sock" "$(< "${docker_log}")" "Does not mount the host Docker socket"
  assert_not_contains " -v " "$(< "${docker_log}")" "Does not mount shared writable host paths"
  assert_contains "ISOLATED_ADMISSION" "${output}" "Emits a secret-free admission receipt"
  assert_contains "ISOLATED_TEARDOWN" "${output}" "Emits a verified teardown receipt"

  RUNNER_GROUP="Default"
  set +e
  output="$(validate_isolated_contract 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails closed for the Default runner group"
)

# -----------------------------------------------------------------------------
# Test 25: supervisor rejects one-shot credentials and cleans up on shutdown
# -----------------------------------------------------------------------------
echo "Test 25: ephemeral supervisor credentials and shutdown"
(
  source "${REPO_ROOT}/entrypoint.sh"
  GITHUB_URL="https://github.com/Verjson/test"
  RUNNER_NAME="isolated-1"
  RUNNER_IMAGE="gha-runner:test"
  RUNNER_EPHEMERAL=1
  RUNNER_TOKEN="one-shot"
  unset GITHUB_PAT RUNNER_TOKEN_CMD || true
  set +e
  output="$(supervise_ephemeral 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects a static token that cannot register the next generation"
  assert_contains "requires GITHUB_PAT or RUNNER_TOKEN_CMD" "${output}" "Requires a renewable credential source"

  cleanup_log="${TMP_DIR}/supervisor_cleanup.log"
  docker() {
    printf '%s\n' "$*" >> "${cleanup_log}"
    [[ "$*" == container\ inspect* ]] && return 1
    return 0
  }
  EPHEMERAL_CHILD_NAME="gha-isolated-1-job"
  output="$(stop_ephemeral_child)"
  assert_contains "stop --time 10 gha-isolated-1-job" "$(< "${cleanup_log}")" "Stops the active child on shutdown"
  assert_contains "rm -f gha-isolated-1-job" "$(< "${cleanup_log}")" "Removes the child after shutdown"
  assert_contains "EPHEMERAL_TEARDOWN" "${output}" "Emits a verified signal teardown receipt"
)

# -----------------------------------------------------------------------------
# Test 26: proxy diagnostics redact credentials without mutating proxy inputs
# -----------------------------------------------------------------------------
echo "Test 26: credential-safe proxy diagnostics"
(
  source "${REPO_ROOT}/entrypoint.sh"
  HTTPS_PROXY="https://runner-user:super-secret@proxy.example.com:8443/path"
  original_proxy="${HTTPS_PROXY}"

  output="$(log_configured_proxy 2>&1)"

  assert_eq "Using proxy: https://proxy.example.com:8443" "${output}" "Redacts proxy userinfo while retaining scheme, host, and port"
  assert_not_contains "runner-user" "${output}" "Omits the proxy username"
  assert_not_contains "super-secret" "${output}" "Omits the proxy password"
  assert_eq "${original_proxy}" "${HTTPS_PROXY}" "Leaves the HTTPS proxy value unchanged for consumers"
)

# -----------------------------------------------------------------------------
# Test 27: proxy diagnostics cover case variants, plain URLs, and failures
# -----------------------------------------------------------------------------
echo "Test 27: proxy diagnostic inputs"
(
  source "${REPO_ROOT}/entrypoint.sh"
  unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy NO_PROXY || true

  HTTP_PROXY="http://proxy.example.com:3128"
  assert_eq "Using proxy: http://proxy.example.com:3128" "$(log_configured_proxy 2>&1)" "Logs a credential-free uppercase proxy"

  unset HTTP_PROXY
  https_proxy="https://lower-user:lower-secret@lower.example.com:9443"
  output="$(log_configured_proxy 2>&1)"
  assert_eq "Using proxy: https://lower.example.com:9443" "${output}" "Supports a credential-bearing lowercase HTTPS proxy"
  assert_not_contains "lower-user" "${output}" "Redacts lowercase proxy usernames"
  assert_not_contains "lower-secret" "${output}" "Redacts lowercase proxy passwords"

  unset https_proxy
  http_proxy="not-a-url:malformed-secret@proxy.example.com"
  output="$(log_configured_proxy 2>&1)"
  assert_eq "Using proxy: <invalid proxy URL>" "${output}" "Uses a safe diagnostic for malformed lowercase proxies"
  assert_not_contains "malformed-secret" "${output}" "Does not expose malformed proxy credentials in failure diagnostics"
  assert_eq "not-a-url:malformed-secret@proxy.example.com" "${http_proxy}" "Leaves malformed proxy input unchanged for consumers"
)

# -----------------------------------------------------------------------------
# Test 28: ci admission verifies zip archive extraction
# -----------------------------------------------------------------------------
echo "Test 28: ci admission verifies zip archive extraction"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_unzip.log"
  mock_passing_ci_tools

  attest_ci_runner >/dev/null

  assert_contains "unzip -v" "$(< "${command_log}")" "Admits unzip so action installers can extract zip release archives"
)

# -----------------------------------------------------------------------------
# Test 29: ci admission fails closed without python3
# -----------------------------------------------------------------------------
echo "Test 29: ci admission fails closed without python3"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_no_python3.log"
  mock_passing_ci_tools
  python3() {
    echo "python3 $*" >> "${command_log}"
    return 127
  }

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects ci admission when python3 is unavailable"
  assert_contains "python3 is unavailable or unhealthy" "${output}" "Identifies python3 as the failed capability"
  assert_contains "python3 --version" "$(< "${command_log}")" "Probes python3 as part of the ci tool contract"
)

# -----------------------------------------------------------------------------
# Test 30: ci admission fails closed without unzip
# -----------------------------------------------------------------------------
echo "Test 30: ci admission fails closed without unzip"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_no_unzip.log"
  mock_passing_ci_tools
  unzip() {
    echo "unzip $*" >> "${command_log}"
    return 127
  }

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects ci admission when unzip is unavailable"
  assert_contains "unzip is unavailable or unhealthy" "${output}" "Identifies unzip as the failed capability"
  assert_not_contains "python3 --version" "$(< "${command_log}")" "Stops admission immediately after the unzip failure"
)

# -----------------------------------------------------------------------------
# Test 31: a missing archive toolchain blocks registration entirely
# -----------------------------------------------------------------------------
echo "Test 31: a missing archive toolchain blocks registration entirely"
(
  source "${REPO_ROOT}/entrypoint.sh"
  toolchain_dir="${TMP_DIR}/toolchain_boundary"
  mkdir -p "${toolchain_dir}"

  cat << 'EOF' > "${toolchain_dir}/config.sh"
#!/usr/bin/env bash
touch config_called
EOF
  cat << 'EOF' > "${toolchain_dir}/run.sh"
#!/usr/bin/env bash
touch run_called
EOF
  chmod +x "${toolchain_dir}/config.sh" "${toolchain_dir}/run.sh"

  GITHUB_URL="https://github.com/my-org"
  GITHUB_PAT="dummy_pat"
  RUNNER_DIR="${toolchain_dir}"
  RUNNER_LABELS="self-hosted,CI"
  command_log=/dev/null
  get_token() {
    touch "${toolchain_dir}/token_minted"
    echo "unexpected_token"
  }
  mock_passing_ci_tools
  unzip() { return 127; }

  set +e
  main >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "1" "${status}" "Main fails closed when the ci archive toolchain is incomplete"
  assert_file_absent "${toolchain_dir}/token_minted" "Does not mint a token without unzip"
  assert_file_absent "${toolchain_dir}/config_called" "Does not register without unzip"
  assert_file_absent "${toolchain_dir}/run_called" "Does not start the runner without unzip"
)

# -----------------------------------------------------------------------------
# Test 32: every material runtime floor fails closed
# -----------------------------------------------------------------------------
echo "Test 32: material runtime version floors"
(
  source "${REPO_ROOT}/entrypoint.sh"

  version_is_at_least "24.10.0" "24.10"
  assert_eq "0" "$?" "Accepts an exact stable runtime floor"

  version_is_at_least "25.0.0" "24.10"
  assert_eq "0" "$?" "Accepts a higher runtime major"

  set +e
  version_is_at_least "24.10garbage" "24.10"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects malformed version output"

  set +e
  version_is_at_least "24.10.0-rc.1" "24.10"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects prerelease versions unless explicitly accepted"

  python3() { echo "Python 3.9.19"; }
  set +e
  output="$(run_python_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects Python below 3.10"
  assert_contains "Python >= 3.10 is required" "${output}" "Reports the Python floor"

  bash() { echo "GNU bash, version 4.2.53(1)-release"; }
  set +e
  output="$(run_bash_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects Bash below 4.3"
  assert_contains "Bash >= 4.3 is required" "${output}" "Reports the Bash floor"

  jq() { echo "jq-1.5"; }
  set +e
  output="$(run_jq_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects jq below 1.6"
  assert_contains "jq >= 1.6 is required" "${output}" "Reports the jq floor"
)

# -----------------------------------------------------------------------------
# Test 33: each newly fixed capability fails closed when missing
# -----------------------------------------------------------------------------
echo "Test 33: newly fixed capabilities fail closed when missing"
for capability in shellcheck cmp diff zstd cc make pkg-config; do
  (
    source "${REPO_ROOT}/entrypoint.sh"
    command_log="${TMP_DIR}/admission_no_${capability}.log"
    mock_passing_ci_tools
    eval "${capability}() { echo '${capability} \$*' >> '${command_log}'; return 127; }"

    set +e
    output="$(attest_ci_runner 2>&1)"
    status=$?
    set -e

    assert_eq "1" "${status}" "Rejects ci admission without ${capability}"
    assert_contains "unavailable or unhealthy" "${output}" "Reports missing ${capability}"
  )
done

(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_no_cxx.log"
  mock_passing_ci_tools
  # An empty PATH means neither c++ nor g++ resolves. Restored immediately afterwards,
  # because the assertion helpers themselves shell out to coreutils.
  empty_path_dir="${TMP_DIR}/no_cxx_path"
  mkdir -p "${empty_path_dir}"
  saved_path="${PATH}"
  PATH="${empty_path_dir}"

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e
  PATH="${saved_path}"

  assert_eq "1" "${status}" "Rejects ci admission without a C++ compiler"
  assert_contains "C++ compiler (c++ or g++) is unavailable" "${output}" \
    "Names both accepted C++ compiler binaries"
)

(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_gxx_only.log"
  mock_passing_ci_tools
  # g++ alone satisfies node-gyp, so it must satisfy admission too.
  gxx_only_dir="${TMP_DIR}/gxx_only_path"
  mkdir -p "${gxx_only_dir}"
  printf '#!/bin/sh\nexit 0\n' > "${gxx_only_dir}/g++"
  chmod +x "${gxx_only_dir}/g++"
  saved_path="${PATH}"
  PATH="${gxx_only_dir}"

  set +e
  run_cxx_admission_check > /dev/null 2>&1
  status=$?
  set -e
  PATH="${saved_path}"

  assert_eq "0" "${status}" "Accepts a toolchain that only provides g++"
)

(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_no_pyyaml.log"
  mock_passing_ci_tools
  python3() {
    echo "python3 $*" >> "${command_log}"
    if [[ "${1:-}" == "--version" ]]; then
      echo "Python 3.13.5"
      return 0
    fi
    return 1
  }

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects ci admission without PyYAML"
  assert_contains "PyYAML is unavailable or unhealthy" "${output}" "Identifies the missing Python module"
)

(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_bad_changelog_cache.log"
  mock_passing_ci_tools
  changelog-tool-cache() {
    echo "changelog-tool-cache $*" >> "${command_log}"
    return 1
  }

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects ci admission when the changelog cache mismatches"
  assert_contains "verified changelog tool cache is unavailable or unhealthy" \
    "${output}" "Identifies the invalid changelog cache"
)

# -----------------------------------------------------------------------------
# Test 34: pwsh label matching is exact and case-insensitive
# -----------------------------------------------------------------------------
echo "Test 34: exact pwsh label matching"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/pwsh_admission.log"
  pwsh() {
    echo "pwsh $*" >> "${command_log}"
    echo "PowerShell 7.6.4"
  }

  labels_include pwsh "self-hosted, PWSH ,ci"
  assert_eq "0" "$?" "Matches pwsh as a trimmed case-insensitive label"

  attest_pwsh_runner >/dev/null
  assert_eq "pwsh --version" "$(< "${command_log}")" "Exercises working PowerShell for pwsh admission"

  set +e
  labels_include pwsh "self-hosted,pwsh-extra,mypwsh"
  status=$?
  set -e
  assert_eq "1" "${status}" "Does not match labels that merely contain pwsh"
)

# -----------------------------------------------------------------------------
# Test 35: missing PowerShell blocks exact pwsh registration before credentials
# -----------------------------------------------------------------------------
echo "Test 35: pwsh admission precedes token minting and registration"
(
  source "${REPO_ROOT}/entrypoint.sh"
  pwsh_dir="${TMP_DIR}/pwsh_boundary"
  mkdir -p "${pwsh_dir}"

  cat << 'EOF' > "${pwsh_dir}/config.sh"
#!/usr/bin/env bash
touch config_called
EOF
  cat << 'EOF' > "${pwsh_dir}/run.sh"
#!/usr/bin/env bash
touch run_called
EOF
  chmod +x "${pwsh_dir}/config.sh" "${pwsh_dir}/run.sh"

  GITHUB_URL="https://github.com/my-org"
  GITHUB_PAT="dummy_pat"
  RUNNER_DIR="${pwsh_dir}"
  RUNNER_LABELS="self-hosted,PwSh"
  get_token() {
    touch "${pwsh_dir}/token_minted"
    echo "unexpected_token"
  }
  pwsh() { return 127; }

  set +e
  output="$(main 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Main fails closed when advertised PowerShell is unavailable"
  assert_contains "PowerShell is unavailable or unhealthy" "${output}" "Identifies failed pwsh admission"
  assert_file_absent "${pwsh_dir}/token_minted" "Does not mint a token after failed pwsh admission"
  assert_file_absent "${pwsh_dir}/config_called" "Does not register after failed pwsh admission"
  assert_file_absent "${pwsh_dir}/run_called" "Does not start after failed pwsh admission"
)

# -----------------------------------------------------------------------------
# Test 36: substring pwsh labels do not claim the capability
# -----------------------------------------------------------------------------
echo "Test 36: non-pwsh labels bypass pwsh admission"
(
  source "${REPO_ROOT}/entrypoint.sh"
  non_pwsh_dir="${TMP_DIR}/non_pwsh_boundary"
  mkdir -p "${non_pwsh_dir}"

  cat << 'EOF' > "${non_pwsh_dir}/config.sh"
#!/usr/bin/env bash
touch config_called
EOF
  cat << 'EOF' > "${non_pwsh_dir}/run.sh"
#!/usr/bin/env bash
touch run_called
EOF
  chmod +x "${non_pwsh_dir}/config.sh" "${non_pwsh_dir}/run.sh"

  GITHUB_URL="https://github.com/my-org"
  unset GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_REMOVE_TOKEN_CMD || true
  RUNNER_TOKEN="mock_token"
  RUNNER_DIR="${non_pwsh_dir}"
  RUNNER_LABELS="self-hosted,pwsh-extra,mypwsh"
  attest_pwsh_runner() {
    touch "${non_pwsh_dir}/unexpected_attestation"
    return 1
  }

  set +e
  main >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "0" "${status}" "Allows registration for labels outside the pwsh contract"
  assert_file_absent "${non_pwsh_dir}/unexpected_attestation" "Uses exact matching before requiring pwsh admission"
  assert_file_exists "${non_pwsh_dir}/config_called" "Registers labels outside the pwsh contract"
  assert_file_exists "${non_pwsh_dir}/run_called" "Starts labels outside the pwsh contract"
)

# -----------------------------------------------------------------------------
# Test 37: default labels follow runtime architecture without replacing overrides
# -----------------------------------------------------------------------------
echo "Test 37: runtime architecture labels"
(
  source "${REPO_ROOT}/entrypoint.sh"

  unset RUNNER_LABELS || true
  uname() { echo "x86_64"; }
  initialize_runner_labels
  assert_eq "self-hosted,linux,x64,docker" "${RUNNER_LABELS}" "Defaults x86_64 runners to x64"

  unset RUNNER_LABELS
  uname() { echo "aarch64"; }
  initialize_runner_labels
  assert_eq "self-hosted,linux,ARM64,docker" "${RUNNER_LABELS}" "Defaults aarch64 runners to ARM64"

  RUNNER_LABELS="self-hosted,linux,custom"
  uname() {
    touch "${TMP_DIR}/unexpected_uname"
    return 1
  }
  initialize_runner_labels
  assert_eq "self-hosted,linux,custom" "${RUNNER_LABELS}" "Preserves explicit runner labels"
  assert_file_absent "${TMP_DIR}/unexpected_uname" "Does not inspect architecture for explicit labels"
)

# -----------------------------------------------------------------------------
# Test 38: child-equivalent supervisor admission precedes every credential mint
# -----------------------------------------------------------------------------
echo "Test 38: child-equivalent supervisor admission precedes token minting"
for capability in ci pwsh; do
  (
    source "${REPO_ROOT}/entrypoint.sh"
    boundary_dir="${TMP_DIR}/supervisor_${capability}_boundary"
    mkdir -p "${boundary_dir}"
    docker_log="${boundary_dir}/docker.log"

    GITHUB_URL="https://github.com/Verjson/test"
    GITHUB_PAT="dummy"
    RUNNER_NAME="${capability}-supervisor"
    RUNNER_LABELS="self-hosted,${capability}"
    RUNNER_IMAGE="gha-runner:${capability}"
    RUNNER_EPHEMERAL=1
    resolve_token() {
      touch "${boundary_dir}/token_minted"
      RUNNER_TOKEN="unexpected"
    }
    docker() {
      echo "$*" >> "${docker_log}"
      if [[ "$*" == run\ --rm*gha-${capability}-supervisor-admission* ]]; then
        return 1
      fi
      return 0
    }
    attest_ci_runner() {
      touch "${boundary_dir}/controller_ci_attestation"
      return 0
    }
    attest_pwsh_runner() {
      touch "${boundary_dir}/controller_pwsh_attestation"
      return 0
    }

    set +e
    supervise_ephemeral >/dev/null 2>&1
    status=$?
    set -e

    assert_eq "1" "${status}" "Supervisor fails closed when ${capability} admission fails"
    assert_file_absent "${boundary_dir}/token_minted" "Does not mint a token before ${capability} admission"
    assert_file_absent "${boundary_dir}/controller_${capability}_attestation" "Does not substitute controller-local ${capability} admission"
    assert_contains "RUNNER_LABELS=self-hosted,${capability}" "$(< "${docker_log}")" "Passes exact labels to the candidate image"
    assert_contains "gha-runner:${capability} admit" "$(< "${docker_log}")" "Invokes credential-free admission in the candidate image"
    assert_not_contains "/var/run/docker.sock" "$(< "${docker_log}")" "Keeps the default admission candidate socketless"
    assert_not_contains "GITHUB_PAT=" "$(< "${docker_log}")" "Does not pass a PAT to candidate admission"
    assert_not_contains "RUNNER_TOKEN=" "$(< "${docker_log}")" "Does not pass a registration token to candidate admission"
  )
done

# -----------------------------------------------------------------------------
# Test 39: candidate admission dispatch checks exact labels without credentials
# -----------------------------------------------------------------------------
echo "Test 39: credential-free candidate admission dispatch"
(
  source "${REPO_ROOT}/entrypoint.sh"
  admission_log="${TMP_DIR}/candidate_admission.log"
  RUNNER_LABELS="self-hosted,CI,PwSh"
  unset GITHUB_URL GITHUB_PAT RUNNER_TOKEN RUNNER_TOKEN_CMD || true
  attest_ci_runner() { echo "ci" >> "${admission_log}"; }
  attest_pwsh_runner() { echo "pwsh" >> "${admission_log}"; }

  main admit

  assert_eq $'ci\npwsh' "$(< "${admission_log}")" "Candidate dispatch admits both exact capability labels"
)

# -----------------------------------------------------------------------------
# Test 40: the host memory budget counts swap toward the OOM survival margin
# -----------------------------------------------------------------------------
echo "Test 40: memory budget parsing"
(
  source "${REPO_ROOT}/entrypoint.sh"
  meminfo="${TMP_DIR}/meminfo"

  printf 'MemTotal:        4009876 kB\nSwapTotal:       4194300 kB\n' > "${meminfo}"
  assert_eq "8011" "$(parse_memory_budget_mb "${meminfo}")" "Sums RAM and swap into a megabyte budget"

  printf 'MemTotal:        4009876 kB\nSwapTotal:             0 kB\n' > "${meminfo}"
  assert_eq "3915" "$(parse_memory_budget_mb "${meminfo}")" "Reports RAM alone when the host has no swap"

  printf 'MemTotal:        4009876 kB\n' > "${meminfo}"
  assert_eq "3915" "$(parse_memory_budget_mb "${meminfo}")" "Treats absent SwapTotal as zero swap"

  set +e
  parse_memory_budget_mb "${TMP_DIR}/missing-meminfo" >/dev/null 2>&1
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails closed when the memory budget is unreadable"

  printf 'SwapTotal:       4194300 kB\n' > "${meminfo}"
  set +e
  parse_memory_budget_mb "${meminfo}" >/dev/null 2>&1
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails closed when MemTotal is absent"

  printf 'MemTotal:        unknown kB\nSwapTotal:       4194300 kB\n' > "${meminfo}"
  set +e
  parse_memory_budget_mb "${meminfo}" >/dev/null 2>&1
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails closed on a non-numeric MemTotal"
)

# -----------------------------------------------------------------------------
# Test 41: too little RAM+swap blocks admission instead of dying mid-job
# -----------------------------------------------------------------------------
echo "Test 41: memory headroom admission"
(
  source "${REPO_ROOT}/entrypoint.sh"

  # The live shared lane: 4 GB RAM + 4 GB swap.
  host_memory_budget_mb() { echo "8011"; }
  set +e
  output="$(RUNNER_MIN_MEMORY_MB=6144 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "0" "${status}" "Admits a host whose RAM+swap clears the minimum"
  assert_contains "8011 MB" "${output}" "Reports the observed budget"

  # The default governs every production host, so it is exercised without an override.
  set +e
  output="$(unset RUNNER_MIN_MEMORY_MB; run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "0" "${status}" "Admits the live lane budget under the default minimum"
  assert_contains "6144 MB" "${output}" "Defaults the minimum to 6144 MB"

  host_memory_budget_mb() { echo "6144"; }
  set +e
  output="$(RUNNER_MIN_MEMORY_MB=6144 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "0" "${status}" "Admits a host exactly at the minimum"

  host_memory_budget_mb() { echo "6143"; }
  set +e
  output="$(RUNNER_MIN_MEMORY_MB=6144 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects a host one megabyte below the minimum"

  # The swapless 4 GB configuration whose kernel killed npm ci.
  host_memory_budget_mb() { echo "3915"; }
  set +e
  output="$(RUNNER_MIN_MEMORY_MB=6144 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects the 4 GB no-swap host that OOM-killed npm ci"
  assert_contains "3915 MB" "${output}" "Names the deficient budget"
  assert_contains "6144 MB" "${output}" "Names the required minimum"

  set +e
  output="$(RUNNER_MIN_MEMORY_MB=not-a-number run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails closed on a non-numeric minimum"

  # A zero-padded minimum would be read as octal by (( )), and the resulting error
  # status reads as "not below the minimum" — admitting every host while logging success.
  set +e
  output="$(RUNNER_MIN_MEMORY_MB=08192 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects a zero-padded minimum instead of admitting on octal error"
  assert_not_contains "Host memory budget:" "${output}" "Does not report success for a rejected minimum"

  set +e
  output="$(RUNNER_MIN_MEMORY_MB=010 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects a zero-padded minimum that would silently parse as octal 8"

  # Past 2^63 a value wraps negative inside (( )) with no error at all, which would make
  # `budget < minimum` false and admit every host.
  host_memory_budget_mb() { echo "512"; }
  set +e
  output="$(RUNNER_MIN_MEMORY_MB=9223372036854775808 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "1" "${status}" "Rejects a minimum wide enough to wrap the arithmetic"
  assert_not_contains "Host memory budget:" "${output}" "Does not report success for an out-of-range minimum"

  set +e
  output="$(RUNNER_MIN_MEMORY_MB=0 run_memory_admission_check 2>&1)"
  status=$?
  set -e
  assert_eq "0" "${status}" "Treats an explicit zero minimum as an opt-out"
  assert_contains "explicitly disabled" "${output}" "Says the minimum was disabled rather than met"

  # The opt-out must not then be defeated by an unreadable budget.
  host_memory_budget_mb() { return 1; }
  set +e
  RUNNER_MIN_MEMORY_MB=0 run_memory_admission_check >/dev/null 2>&1
  status=$?
  set -e
  assert_eq "0" "${status}" "Honours the opt-out even when the budget is unreadable"
)


# -----------------------------------------------------------------------------
# Test 42: a prior kernel OOM kill is reported explicitly, not as a lost log
# -----------------------------------------------------------------------------
echo "Test 42: OOM kill post-mortem reporting"
(
  source "${REPO_ROOT}/entrypoint.sh"
  vmstat="${TMP_DIR}/vmstat"

  printf 'nr_free_pages 12345\noom_kill 2\npgfault 99\n' > "${vmstat}"
  assert_eq "2" "$(parse_oom_kill_count "${vmstat}")" "Reads the kernel's cumulative kill counter"

  printf 'nr_free_pages 12345\noom_kill 0\n' > "${vmstat}"
  assert_eq "0" "$(parse_oom_kill_count "${vmstat}")" "Reads a clean host as zero kills"

  # oom_kill_process is a different, adjacent counter; a prefix match would misreport.
  printf 'oom_kill_process 7\noom_kill 3\n' > "${vmstat}"
  assert_eq "3" "$(parse_oom_kill_count "${vmstat}")" "Does not match an adjacent counter name"

  printf 'nr_free_pages 12345\n' > "${vmstat}"
  set +e
  parse_oom_kill_count "${vmstat}" >/dev/null 2>&1
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails when the counter is absent"

  set +e
  parse_oom_kill_count "${TMP_DIR}/missing-vmstat" >/dev/null 2>&1
  status=$?
  set -e
  assert_eq "1" "${status}" "Fails when the counter file is unreadable"

  parse_oom_kill_count() { echo "2"; }
  output="$(report_prior_oom_kills 2>&1)"
  assert_contains "OOM WARNING" "${output}" "Announces prior kills in greppable terms"
  assert_contains "terminated 2 process(es)" "${output}" "States the exact kill count"

  parse_oom_kill_count() { echo "0"; }
  assert_eq "" "$(report_prior_oom_kills 2>&1)" "Stays silent on a host with no kills"

  # The path a locked-down host takes: silence here must not read as "no kills".
  parse_oom_kill_count() { return 1; }
  set +e
  output="$(report_prior_oom_kills 2>&1)"
  status=$?
  set -e
  assert_eq "0" "${status}" "An unreadable counter does not fail admission"
  assert_contains "unavailable" "${output}" "Reports that the post-mortem could not run"
  assert_not_contains "OOM WARNING" "${output}" "Does not claim kills it could not observe"
)

# -----------------------------------------------------------------------------
# Test 43: registration proves host capacity before minting a credential
# -----------------------------------------------------------------------------
echo "Test 43: host capacity is proven before any credential is touched"
(
  source "${REPO_ROOT}/entrypoint.sh"
  order_log="${TMP_DIR}/capacity_order.log"
  RUNNER_LABELS="self-hosted,general"
  GITHUB_URL="https://github.com/Verjson"
  GITHUB_PAT_FIFO="${TMP_DIR}/pat.fifo"
  RUNNER_DIR="${TMP_DIR}"

  report_prior_oom_kills() { echo "oom-report" >> "${order_log}"; }
  run_memory_admission_check() { echo "memory" >> "${order_log}"; return 1; }
  consume_github_pat() { echo "consume-pat" >> "${order_log}"; }
  resolve_token() { echo "resolve-token" >> "${order_log}"; }
  attest_runner_labels() { echo "labels" >> "${order_log}"; }

  set +e
  main >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "1" "${status}" "A deficient host fails before registering"
  assert_eq $'oom-report\nmemory' "$(< "${order_log}")" \
    "Reports OOM history then rejects, touching neither the PAT FIFO nor a token"
)

# -----------------------------------------------------------------------------
# Test 44: an undersized host is rejected once, not per supervised job
# -----------------------------------------------------------------------------
echo "Test 44: supervisor proves host capacity outside the job loop"
(
  source "${REPO_ROOT}/entrypoint.sh"
  order_log="${TMP_DIR}/supervisor_capacity.log"
  RUNNER_IMAGE="gha-runner:base"
  RUNNER_NAME="probe"
  GITHUB_URL="https://github.com/Verjson"
  GITHUB_PAT="pat"
  RUNNER_EPHEMERAL="true"
  RUNNER_LABELS="self-hosted,untrusted-pr"

  run_memory_admission_check() { echo "memory" >> "${order_log}"; return 1; }
  report_prior_oom_kills() { :; }
  supervise_ephemeral() { echo "supervise" >> "${order_log}"; }
  resolve_token() { echo "token" >> "${order_log}"; }

  set +e
  main supervise >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "1" "${status}" "Supervision fails closed on an undersized host"
  assert_eq "memory" "$(< "${order_log}")" \
    "Never enters the job loop, so no token is minted per retry"
)

# -----------------------------------------------------------------------------
# Test 45: the standalone ci probe still consumes its PAT FIFO
# -----------------------------------------------------------------------------
echo "Test 45: ci admission keeps the one-use PAT transport"
(
  source "${REPO_ROOT}/entrypoint.sh"
  order_log="${TMP_DIR}/ci_pat_order.log"

  consume_github_pat() { echo "consume-pat" >> "${order_log}"; }
  attest_host_capacity() { echo "capacity" >> "${order_log}"; }
  attest_ci_runner() { echo "ci" >> "${order_log}"; }

  main ci >/dev/null 2>&1

  assert_eq $'consume-pat\nci' "$(< "${order_log}")" \
    "Consumes the PAT then attests, without imposing a host check on an image probe"
)

# -----------------------------------------------------------------------------
# Test 46: claim_work_root records the holding runner's identity
# -----------------------------------------------------------------------------
echo "Test 46: claim_work_root records the holding runner's identity"
(
  source "${REPO_ROOT}/entrypoint.sh"
  claim_dir="${TMP_DIR}/claim_root"
  mkdir -p "${claim_dir}"
  cd "${claim_dir}"
  RUNNER_NAME="gha-general-10"
  RUNNER_WORKDIR="_work"

  claim_work_root
  status=$?

  assert_eq "0" "${status}" "Claims an unclaimed work root"
  assert_file_exists "${claim_dir}/_work/.gha-work-root.lock" "Records the claim in the work root"
  assert_contains "runner=gha-general-10" "$(< "${claim_dir}/_work/.gha-work-root.lock")" \
    "Names the claiming runner for operator diagnostics"
  assert_contains "pid=$$" "$(< "${claim_dir}/_work/.gha-work-root.lock")" \
    "Records the claiming process id for operator diagnostics"
)

# -----------------------------------------------------------------------------
# Test 47: claim_work_root fails closed against an already-claimed work root
# -----------------------------------------------------------------------------
echo "Test 47: claim_work_root fails closed against an already-claimed work root"
(
  source "${REPO_ROOT}/entrypoint.sh"
  claim_dir="${TMP_DIR}/claim_conflict"
  mkdir -p "${claim_dir}/_work"
  cd "${claim_dir}"

  # Hold the lock from a real, still-running background process — the scenario a
  # same-process re-claim cannot exercise, since a process always holds its own flock.
  holder_log="${TMP_DIR}/claim_conflict_holder.log"
  (
    exec 9>>"_work/.gha-work-root.lock"
    flock 9
    printf 'runner=gha-general-9 pid=%s\n' "$$" > "_work/.gha-work-root.lock"
    echo ready >> "${holder_log}"
    sleep 5
  ) &
  holder_pid=$!
  for _ in $(seq 1 50); do
    [[ -s "${holder_log}" ]] && break
    sleep 0.1
  done

  RUNNER_NAME="gha-general-10"
  RUNNER_WORKDIR="_work"
  set +e
  output="$(claim_work_root 2>&1)"
  status=$?
  set -e
  kill "${holder_pid}" 2>/dev/null || true
  wait "${holder_pid}" 2>/dev/null || true

  assert_eq "1" "${status}" "Refuses a work root another live runner process already holds"
  assert_contains "already claimed by another active runner process" "${output}" \
    "Explains the collision rather than silently sharing the checkout"
  assert_contains "gha-general-9" "${output}" "Names the other holder so operators can find the collision"
)

# -----------------------------------------------------------------------------
# Test 48: main claims the work root before resolving any registration token
# -----------------------------------------------------------------------------
echo "Test 48: main claims the work root before token resolution"
(
  source "${REPO_ROOT}/entrypoint.sh"
  order_log="${TMP_DIR}/claim_order.log"
  RUNNER_DIR="${TMP_DIR}/claim_order_dir"
  mkdir -p "${RUNNER_DIR}"
  GITHUB_URL="https://github.com/Verjson"
  RUNNER_LABELS="self-hosted,general"

  attest_host_capacity() { echo "capacity" >> "${order_log}"; }
  attest_general_bridge_routing() { echo "bridge" >> "${order_log}"; }
  consume_github_pat() { echo "consume-pat" >> "${order_log}"; }
  claim_work_root() { echo "claim" >> "${order_log}"; return 1; }
  resolve_token() { echo "resolve-token" >> "${order_log}"; }
  attest_runner_labels() { echo "labels" >> "${order_log}"; }

  set +e
  main >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "1" "${status}" "A refused work-root claim fails main before registration"
  assert_eq $'capacity\nbridge\nconsume-pat\nclaim' "$(< "${order_log}")" \
    "Claims the work root after host admission but before label tools or token resolution"
)

# -----------------------------------------------------------------------------
# Test 49: a general runner proves Docker bridge routing before credentials
# -----------------------------------------------------------------------------
echo "Test 49: general bridge routing is proven before any credential is touched"
(
  source "${REPO_ROOT}/entrypoint.sh"
  order_log="${TMP_DIR}/bridge_order.log"
  RUNNER_LABELS="self-hosted,general"
  GITHUB_URL="https://github.com/Verjson"

  attest_host_capacity() { echo "capacity" >> "${order_log}"; }
  attest_general_bridge_routing() { echo "bridge" >> "${order_log}"; return 1; }
  consume_github_pat() { echo "consume-pat" >> "${order_log}"; }
  resolve_token() { echo "resolve-token" >> "${order_log}"; }

  set +e
  main >/dev/null 2>&1
  status=$?
  set -e

  assert_eq "1" "${status}" "A bridge-isolated general host fails before registering"
  assert_eq $'capacity\nbridge' "$(< "${order_log}")" \
    "Rejects the host before consuming a PAT or resolving a registration token"
)

# -----------------------------------------------------------------------------
# Test 50: bridge admission reaches a sibling and always removes the probe
# -----------------------------------------------------------------------------
echo "Test 50: bridge admission reaches and removes an exact sibling probe"
(
  source "${REPO_ROOT}/entrypoint.sh"
  docker_log="${TMP_DIR}/bridge_docker.log"
  curl_log="${TMP_DIR}/bridge_curl.log"
  RUNNER_BRIDGE_PROBE_IMAGE="sha256:$(printf 'a%.0s' {1..64})"
  RUNNER_NAME="gha-general-4"
  HOSTNAME="runner-container"

  docker() {
    echo "$*" >> "${docker_log}"
    case "$1" in
      run) echo "probe-container-id" ;;
      inspect) echo "172.17.0.23" ;;
    esac
  }
  curl() {
    echo "$*" >> "${curl_log}"
    return 0
  }
  sleep() { :; }

  attest_general_bridge_routing "self-hosted, General "

  assert_contains "run -d --rm --name" "$(< "${docker_log}")" \
    "Starts a disposable sibling from the exact configured image"
  assert_contains "--network bridge --entrypoint python3 ${RUNNER_BRIDGE_PROBE_IMAGE}" \
    "$(< "${docker_log}")" "Pins the probe to Docker's bridge and a non-runner entrypoint"
  assert_contains "http://172.17.0.23:18080/" "$(< "${curl_log}")" \
    "Tests the sibling's bridge address rather than host loopback"
  assert_contains "rm -f" "$(< "${docker_log}")" "Removes the disposable probe after success"
)

# -----------------------------------------------------------------------------
# Test 51: labels that merely contain general do not claim bridge capability
# -----------------------------------------------------------------------------
echo "Test 51: bridge admission uses an exact case-insensitive general label"
(
  source "${REPO_ROOT}/entrypoint.sh"
  docker() { touch "${TMP_DIR}/unexpected_bridge_probe"; return 1; }

  attest_general_bridge_routing "self-hosted,general-purpose"

  assert_file_absent "${TMP_DIR}/unexpected_bridge_probe" \
    "Does not impose the general-lane contract on substring labels"
)

# -----------------------------------------------------------------------------
# Test 52: bridge admission cannot pull a mutable probe image
# -----------------------------------------------------------------------------
echo "Test 52: bridge admission rejects mutable probe images"
(
  source "${REPO_ROOT}/entrypoint.sh"
  RUNNER_BRIDGE_PROBE_IMAGE="ghcr.io/verjson/gha-runner:latest"
  docker() { touch "${TMP_DIR}/mutable_probe_started"; return 0; }

  set +e
  output="$(attest_general_bridge_routing "self-hosted,general" 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Fails closed on a mutable bridge probe image"
  assert_contains "immutable sha256 image ID" "${output}" "Explains the immutable local-image contract"
  assert_file_absent "${TMP_DIR}/mutable_probe_started" "Rejects the image before Docker can pull or start it"
)

echo "-----------------------------------------------------------------------------"
passed_count=$(find "${TMP_DIR}" -name 'passed_*' | wc -l | tr -d ' ')
failed_count=$(find "${TMP_DIR}" -name 'failed_*' | wc -l | tr -d ' ')

echo "Test Summary: ${passed_count} passed, ${failed_count} failed"
if [[ ${failed_count} -gt 0 ]]; then
  exit 1
fi
