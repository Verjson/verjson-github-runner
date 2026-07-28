#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
RUNNER_DIR="${TMP_DIR}/runner"
mkdir -p "${RUNNER_DIR}/bin"

cleanup_test() {
  local pid_file
  for pid_file in \
    "${RUNNER_DIR}/worker.pid" \
    "${RUNNER_DIR}/listener.pid" \
    "${RUNNER_DIR}/helper.pid" \
    "${RUNNER_DIR}/wrapper.pid"; do
    if [[ -s "${pid_file}" ]]; then
      kill -KILL "$(< "${pid_file}")" 2>/dev/null || true
    fi
  done
  rm -rf "${TMP_DIR}"
}
trap cleanup_test EXIT

cat > "${RUNNER_DIR}/config.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> config.log
EOF

# Match the pinned Actions runner topology: run.sh is a wrapper, run-helper.sh
# invokes Runner.Listener, and the listener schedules Runner.Worker.
cat > "${RUNNER_DIR}/run.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > wrapper.pid
./run-helper.sh
EOF
cat > "${RUNNER_DIR}/run-helper.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$$" > helper.pid
./bin/Runner.Listener
EOF
cat > "${RUNNER_DIR}/bin/Runner.Listener" <<'EOF'
#!/usr/bin/env bash
env | sort > listener.env
printf '%s\n' "$$" > listener.pid
./bin/Runner.Worker &
worker_pid=$!
trap 'kill -TERM "${worker_pid}" 2>/dev/null || true; wait "${worker_pid}" 2>/dev/null || true; exit 0' TERM INT
wait "${worker_pid}"
EOF
cat > "${RUNNER_DIR}/bin/Runner.Worker" <<'EOF'
#!/usr/bin/env bash
env | sort > worker.env
printf '%s\n' "$$" > worker.pid
# Exercise the bounded hard-stop path: an untrusted job can ignore TERM.
trap '' TERM INT
while :; do sleep 1; done
EOF
chmod +x \
  "${RUNNER_DIR}/config.sh" \
  "${RUNNER_DIR}/run.sh" \
  "${RUNNER_DIR}/run-helper.sh" \
  "${RUNNER_DIR}/bin/Runner.Listener" \
  "${RUNNER_DIR}/bin/Runner.Worker"
cat > "${TMP_DIR}/bash-env.sh" <<'EOF'
export INJECTED_TOKEN="bash-env-sentinel"
EOF

(
  export GITHUB_URL="https://github.com/Verjson/test"
  export RUNNER_DIR
  export RUNNER_EPHEMERAL=1
  export GITHUB_PAT="github-pat-sentinel"
  export RUNNER_TOKEN="runner-token-sentinel"
  export RUNNER_TOKEN_CMD="token-command-sentinel"
  export RUNNER_REMOVE_TOKEN_CMD="remove-command-sentinel"
  export GH_TOKEN="gh-token-sentinel"
  export GITHUB_TOKEN="github-token-sentinel"
  export ACTIONS_RUNTIME_TOKEN="actions-runtime-sentinel"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="actions-id-sentinel"
  export AWS_ACCESS_KEY_ID="aws-access-sentinel"
  export AWS_SECRET_ACCESS_KEY="aws-secret-sentinel"
  export AWS_SESSION_TOKEN="aws-session-sentinel"
  export GOOGLE_APPLICATION_CREDENTIALS="google-credentials-sentinel"
  export AZURE_CLIENT_SECRET="azure-secret-sentinel"
  export DOCKER_AUTH_CONFIG="docker-auth-sentinel"
  export TEST_PASSWORD="password-sentinel"
  export SSH_PRIVATE_KEY="private-key-sentinel"
  export BASH_ENV="${TMP_DIR}/bash-env.sh"

  source "${REPO_ROOT}/entrypoint.sh"
  get_token() {
    if [[ "$1" == "registration" ]]; then
      printf 'fresh-registration-token\n'
    else
      printf 'fresh-removal-token\n'
    fi
  }
  main
) > "${RUNNER_DIR}/entrypoint.log" 2>&1 &
entrypoint_pid=$!

for _ in $(seq 1 100); do
  if [[ -s "${RUNNER_DIR}/worker.pid" && -s "${RUNNER_DIR}/listener.env" && -s "${RUNNER_DIR}/worker.env" ]]; then
    break
  fi
  sleep 0.1
done
[[ -s "${RUNNER_DIR}/worker.pid" ]] || {
  echo "topology-faithful runner did not reach Runner.Worker" >&2
  exit 1
}

credential_name_pattern='^(GITHUB_PAT|RUNNER_TOKEN|RUNNER_TOKEN_CMD|RUNNER_REMOVE_TOKEN_CMD|GH_TOKEN|GITHUB_TOKEN|ACTIONS_RUNTIME_TOKEN|ACTIONS_ID_TOKEN_REQUEST_TOKEN|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN|GOOGLE_APPLICATION_CREDENTIALS|AZURE_CLIENT_SECRET|DOCKER_AUTH_CONFIG|TEST_PASSWORD|SSH_PRIVATE_KEY)='
for child_env in "${RUNNER_DIR}/listener.env" "${RUNNER_DIR}/worker.env"; do
  if grep -Eq "${credential_name_pattern}" "${child_env}"; then
    echo "scheduled runner process inherited a credential-bearing variable:" >&2
    grep -E "${credential_name_pattern}" "${child_env}" >&2
    exit 1
  fi
  if grep -Eq 'sentinel|fresh-registration-token|fresh-removal-token' "${child_env}"; then
    echo "scheduled runner process inherited credential material" >&2
    exit 1
  fi
  grep -q '^GITHUB_URL=https://github.com/Verjson/test$' "${child_env}" || {
    echo "runner child lost required non-credential configuration" >&2
    exit 1
  }
  grep -q '^PATH=' "${child_env}" || {
    echo "runner child lost PATH while credentials were scrubbed" >&2
    exit 1
  }
done

kill -TERM "${entrypoint_pid}"
set +e
wait "${entrypoint_pid}"
shutdown_status=$?
set -e
[[ "${shutdown_status}" -eq 143 ]] || {
  printf 'supervised shutdown status was not preserved: %s\n' "${shutdown_status}" >&2
  exit 1
}
grep -q 'Runner process group did not stop within 5 seconds; forcing termination.' \
  "${RUNNER_DIR}/entrypoint.log" || {
  echo "uncooperative Worker did not exercise the bounded group-wide KILL path" >&2
  exit 1
}
if grep -Eq 'sentinel|fresh-registration-token|fresh-removal-token' "${RUNNER_DIR}/entrypoint.log"; then
  echo "entrypoint diagnostics exposed credential material" >&2
  exit 1
fi

for pid_file in \
  "${RUNNER_DIR}/wrapper.pid" \
  "${RUNNER_DIR}/helper.pid" \
  "${RUNNER_DIR}/listener.pid" \
  "${RUNNER_DIR}/worker.pid"; do
  pid="$(< "${pid_file}")"
  if kill -0 "${pid}" 2>/dev/null; then
    printf 'supervised runner process survived shutdown: %s (%s)\n' "${pid}" "${pid_file}" >&2
    exit 1
  fi
done

grep -q '^remove --token fresh-removal-token$' "${RUNNER_DIR}/config.log" || {
  echo "de-registration did not run after the complete process group stopped" >&2
  exit 1
}

printf 'runner process-group and credential redaction tests passed\n'
