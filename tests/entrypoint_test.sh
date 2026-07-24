#!/usr/bin/env bash
set -euo pipefail

# Unit test suite for entrypoint.sh token resolution and cleanup logic

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

echo "-----------------------------------------------------------------------------"
passed_count=$(find "${TMP_DIR}" -name 'passed_*' | wc -l | tr -d ' ')
failed_count=$(find "${TMP_DIR}" -name 'failed_*' | wc -l | tr -d ' ')

echo "Test Summary: ${passed_count} passed, ${failed_count} failed"
if [[ ${failed_count} -gt 0 ]]; then
  exit 1
fi
