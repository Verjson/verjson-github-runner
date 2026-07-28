#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

make_runner() {
  local name="$1"
  local exit_code="$2"
  local runner_dir="${TMP_DIR}/${name}"

  mkdir -p "${runner_dir}"
  cat > "${runner_dir}/config.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> config.log
EOF
  cat > "${runner_dir}/run.sh" <<EOF
#!/usr/bin/env bash
exit ${exit_code}
EOF
  chmod +x "${runner_dir}/config.sh" "${runner_dir}/run.sh"
  printf '%s\n' "${runner_dir}"
}

run_main() {
  local runner_dir="$1"
  local mode="$2"

  (
    export GITHUB_URL="https://github.com/Verjson/test"
    export RUNNER_TOKEN="test-token"
    export RUNNER_DIR="${runner_dir}"
    export RUNNER_EPHEMERAL="${mode}"
    source "${REPO_ROOT}/entrypoint.sh"
    main
  )
}

normal_dir="$(make_runner normal 0)"
run_main "${normal_dir}" 1
grep -q '^remove --local$' "${normal_dir}/config.log" || {
  echo "normal one-job completion did not de-register the runner" >&2
  exit 1
}

crash_dir="$(make_runner crash 17)"
set +e
run_main "${crash_dir}" true
crash_status=$?
set -e
[[ "${crash_status}" -eq 17 ]] || {
  printf 'runner crash status was not preserved: %s\n' "${crash_status}" >&2
  exit 1
}
grep -q '^remove --local$' "${crash_dir}/config.log" || {
  echo "runner crash did not attempt de-registration" >&2
  exit 1
}

refresh_dir="$(make_runner refresh 0)"
cat > "${TMP_DIR}/mint-token.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
touch "${TMP_DIR}/token-mints.log"
count="\$(wc -l < "${TMP_DIR}/token-mints.log")"
printf 'mint\\n' >> "${TMP_DIR}/token-mints.log"
printf 'fresh-token-%s\\n' "\$((count + 1))"
EOF
chmod +x "${TMP_DIR}/mint-token.sh"
for _ in 1 2; do
  (
    export GITHUB_URL="https://github.com/Verjson/test"
    export RUNNER_TOKEN_CMD="${TMP_DIR}/mint-token.sh"
    unset RUNNER_TOKEN GITHUB_PAT
    export RUNNER_DIR="${refresh_dir}"
    export RUNNER_EPHEMERAL=1
    source "${REPO_ROOT}/entrypoint.sh"
    main
  )
done
[[ "$(wc -l < "${TMP_DIR}/token-mints.log")" -eq 2 ]] || {
  echo "separate ephemeral registrations did not mint separate tokens" >&2
  exit 1
}
grep -q -- '--token fresh-token-1' "${refresh_dir}/config.log" || {
  echo "first fresh registration token was not used" >&2
  exit 1
}
grep -q -- '--token fresh-token-2' "${refresh_dir}/config.log" || {
  echo "second fresh registration token was not used" >&2
  exit 1
}

invalid_dir="$(make_runner invalid 0)"
set +e
invalid_output="$(run_main "${invalid_dir}" yes 2>&1)"
invalid_status=$?
set -e
[[ "${invalid_status}" -ne 0 ]] || {
  echo "invalid RUNNER_EPHEMERAL unexpectedly started" >&2
  exit 1
}
[[ "${invalid_output}" == *"RUNNER_EPHEMERAL must be one of"* ]] || {
  echo "invalid RUNNER_EPHEMERAL did not fail with the expected error" >&2
  exit 1
}
[[ ! -e "${invalid_dir}/config.log" ]] || {
  echo "invalid RUNNER_EPHEMERAL reached registration" >&2
  exit 1
}

shutdown_dir="$(make_runner shutdown 0)"
cat > "${shutdown_dir}/run.sh" <<'EOF'
#!/usr/bin/env bash
trap 'printf "terminated\n" >> run.log; exit 0' TERM
printf '%s\n' "$$" > run.pid
while :; do sleep 1; done
EOF
chmod +x "${shutdown_dir}/run.sh"
(
  export GITHUB_URL="https://github.com/Verjson/test"
  export RUNNER_TOKEN="test-token"
  export RUNNER_DIR="${shutdown_dir}"
  export RUNNER_EPHEMERAL=1
  exec bash "${REPO_ROOT}/entrypoint.sh"
) &
entrypoint_pid=$!
for _ in $(seq 1 50); do
  [[ -s "${shutdown_dir}/run.pid" ]] && break
  sleep 0.1
done
[[ -s "${shutdown_dir}/run.pid" ]] || {
  echo "shutdown runner did not start" >&2
  exit 1
}
runner_pid="$(< "${shutdown_dir}/run.pid")"
kill -TERM "${entrypoint_pid}"
set +e
wait "${entrypoint_pid}"
shutdown_status=$?
set -e
[[ "${shutdown_status}" -eq 143 ]] || {
  printf 'shutdown status was not preserved: %s\n' "${shutdown_status}" >&2
  exit 1
}
if kill -0 "${runner_pid}" 2>/dev/null; then
  echo "runner child survived entrypoint shutdown" >&2
  exit 1
fi
grep -q '^terminated$' "${shutdown_dir}/run.log" || {
  echo "entrypoint did not forward shutdown to the runner process" >&2
  exit 1
}
grep -q '^remove --local$' "${shutdown_dir}/config.log" || {
  echo "shutdown did not attempt runner de-registration" >&2
  exit 1
}

printf 'entrypoint lifecycle tests passed\n'
