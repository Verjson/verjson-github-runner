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
  assert_eq "mock_pat_token" "${runner_registration_token}" "Resolves token via GITHUB_PAT"
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
  assert_eq "mock_cmd_token" "${runner_registration_token}" "Resolves token via RUNNER_TOKEN_CMD"
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
  assert_eq "mock_static_token" "${runner_registration_token}" "Preserves static RUNNER_TOKEN"
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
EOF
  chmod +x "${TEST_RUNNER_DIR}/config.sh" "${TEST_RUNNER_DIR}/run.sh"

  export GITHUB_URL="https://github.com/my-org/my-repo"
  export RUNNER_TOKEN="mock_token"
  export RUNNER_DIR="${TEST_RUNNER_DIR}"
  export RUNNER_EPHEMERAL=1

  source "${REPO_ROOT}/entrypoint.sh"
  main &
  main_pid=$!
  sleep 1
  kill -TERM $main_pid 2>/dev/null || true
  wait $main_pid 2>/dev/null || true

  assert_contains "--ephemeral" "$(< "${TEST_RUNNER_DIR}/config_args.log")" "Passes --ephemeral flag when RUNNER_EPHEMERAL is set"
  assert_contains "run.sh executed" "$(< "${TEST_RUNNER_DIR}/run_exec.log")" "Launches run.sh in working directory"
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

  gh() { echo "gh $*" >> "${command_log}"; }
  docker() { echo "docker $*" >> "${command_log}"; }
  node() {
    echo "node $*" >> "${command_log}"
    echo "v24.18.0"
  }
  npm() { echo "npm $*" >> "${command_log}"; }
  jq() { echo "jq $*" >> "${command_log}"; }
  git() { echo "git $*" >> "${command_log}"; }
  bash() { echo "bash $*" >> "${command_log}"; }
  curl() { echo "curl $*" >> "${command_log}"; }
  grep() { echo "grep $*" >> "${command_log}"; }
  sed() { echo "sed $*" >> "${command_log}"; }
  awk() { echo "awk $*" >> "${command_log}"; }
  find() { echo "find $*" >> "${command_log}"; }
  base64() { echo "base64 $*" >> "${command_log}"; }
  tar() { echo "tar $*" >> "${command_log}"; }
  gzip() { echo "gzip $*" >> "${command_log}"; }

  attest_ci_runner >/dev/null

  expected_commands=$'gh --version\ndocker version\ndocker compose version\ndocker buildx version\nnode --version\nnpm --version\njq --version\ngit --version\nbash --version\ncurl --version\ngrep --version\nsed --version\nawk --version\nfind --version\nbase64 --version\ntar --version\ngzip --version'
  assert_eq "${expected_commands}" "$(< "${command_log}")" "Exercises every required ci capability"
)

# -----------------------------------------------------------------------------
# Test 16: failing ci admission stops at the failed capability
# -----------------------------------------------------------------------------
echo "Test 16: failing ci admission stops at the failed capability"
(
  source "${REPO_ROOT}/entrypoint.sh"
  command_log="${TMP_DIR}/admission_fail.log"

  gh() { echo "gh $*" >> "${command_log}"; }
  docker() {
    echo "docker $*" >> "${command_log}"
    [[ "$*" != "version" ]]
  }
  node() { echo "node $*" >> "${command_log}"; }
  npm() { echo "npm $*" >> "${command_log}"; }
  jq() { echo "jq $*" >> "${command_log}"; }
  git() { echo "git $*" >> "${command_log}"; }
  bash() { echo "bash $*" >> "${command_log}"; }

  set +e
  output="$(attest_ci_runner 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects ci admission when a required capability fails"
  assert_contains "Docker daemon is unavailable or unhealthy" "${output}" "Identifies the failed capability"
  assert_eq $'gh --version\ndocker version' "$(< "${command_log}")" "Stops admission immediately after failure"
)

# -----------------------------------------------------------------------------
# Test 17: ci admission rejects the wrong Node.js major
# -----------------------------------------------------------------------------
echo "Test 17: ci admission rejects the wrong Node.js major"
(
  source "${REPO_ROOT}/entrypoint.sh"
  node() { echo "v23.11.0"; }

  set +e
  output="$(run_node_24_admission_check 2>&1)"
  status=$?
  set -e

  assert_eq "1" "${status}" "Rejects Node.js outside major 24"
  assert_contains "Node.js major 24 is required" "${output}" "Reports the required Node.js major"
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

  gh() { echo "gh $*" >> "${command_log}"; }
  docker() { echo "docker $*" >> "${command_log}"; }
  node() {
    echo "node $*" >> "${command_log}"
    echo "v24.18.0"
  }
  npm() { echo "npm $*" >> "${command_log}"; }
  jq() { echo "jq $*" >> "${command_log}"; }
  git() { echo "git $*" >> "${command_log}"; }
  bash() { echo "bash $*" >> "${command_log}"; }
  curl() { echo "curl $*" >> "${command_log}"; }
  grep() { echo "grep $*" >> "${command_log}"; }
  sed() { echo "sed $*" >> "${command_log}"; }
  awk() { echo "awk $*" >> "${command_log}"; }
  find() { echo "find $*" >> "${command_log}"; }
  base64() { echo "base64 $*" >> "${command_log}"; }
  tar() { echo "tar $*" >> "${command_log}"; }
  gzip() { echo "gzip $*" >> "${command_log}"; }
  export -f gh docker node npm jq git bash curl grep sed awk find base64 tar gzip

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

  expected_commands=$'gh --version\ndocker version\ndocker compose version\ndocker buildx version\nnode --version\nnpm --version\njq --version\ngit --version\nbash --version\ncurl --version\ngrep --version\nsed --version\nawk --version\nfind --version\nbase64 --version\ntar --version\ngzip --version'
  assert_eq "0" "${status}" "Standalone ci exits successfully without registration inputs"
  assert_eq "${expected_commands}" "$(< "${command_log}")" "Dispatches directly to the complete ci attestation"
  assert_file_absent "${standalone_dir}/token_resolved" "Does not resolve a registration token"
  assert_file_absent "${standalone_dir}/config_called" "Does not invoke config.sh"
  assert_contains "CI runner admission passed." "${output}" "Reports successful standalone admission"
)

echo "-----------------------------------------------------------------------------"
passed_count=$(find "${TMP_DIR}" -name 'passed_*' | wc -l | tr -d ' ')
failed_count=$(find "${TMP_DIR}" -name 'failed_*' | wc -l | tr -d ' ')

echo "Test Summary: ${passed_count} passed, ${failed_count} failed"
if [[ ${failed_count} -gt 0 ]]; then
  exit 1
fi
