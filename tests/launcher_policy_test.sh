#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DOCKER_COMMAND_LOG}"
EOF
chmod +x "${TMP_DIR}/bin/docker"

run_setup() {
  local mode="$1"
  local log="$2"

  PATH="${TMP_DIR}/bin:${PATH}" DOCKER_COMMAND_LOG="${log}" \
    bash "${REPO_ROOT}/setup.sh" <<EOF
https://github.com/Verjson/test
test-pat
test-runner
self-hosted,linux
Default
_work
${mode}
EOF
}

ephemeral_log="${TMP_DIR}/ephemeral.log"
run_setup true "${ephemeral_log}" >/dev/null
grep -q -- '--rm' "${ephemeral_log}" || {
  echo "setup.sh ephemeral mode did not use --rm" >&2
  exit 1
}
grep -q -- 'RUNNER_EPHEMERAL=1' "${ephemeral_log}" || {
  echo "setup.sh ephemeral mode did not explicitly enable one-job registration" >&2
  exit 1
}
if grep -q -- '--restart' "${ephemeral_log}"; then
  echo "setup.sh ephemeral mode installed a restart policy" >&2
  exit 1
fi

persistent_log="${TMP_DIR}/persistent.log"
run_setup false "${persistent_log}" >/dev/null
grep -q -- '--restart unless-stopped' "${persistent_log}" || {
  echo "setup.sh persistent mode lost its restart policy" >&2
  exit 1
}
if grep -q -- '--rm' "${persistent_log}"; then
  echo "setup.sh persistent mode unexpectedly used --rm" >&2
  exit 1
fi

grep -q '\$lifecycleArgs' "${REPO_ROOT}/setup.ps1" || {
  echo "setup.ps1 does not apply an explicit lifecycle argument set" >&2
  exit 1
}
grep -q 'RUNNER_EPHEMERAL=1' "${REPO_ROOT}/setup.ps1" || {
  echo "setup.ps1 cannot launch one-job registration" >&2
  exit 1
}

compose_env="${TMP_DIR}/compose.env"
cat > "${compose_env}" <<'EOF'
GITHUB_URL=https://github.com/Verjson/test
GITHUB_PAT=test
RUNNER_NAME=test
RUNNER_LABELS=self-hosted
EOF
compose_json="$(
  cd "${REPO_ROOT}"
  RUNNER_ENV_FILE="${compose_env}" \
    docker compose --profile ephemeral config --format json
)"
jq -e '
  .services.runner.environment.RUNNER_EPHEMERAL == "0" and
  .services["runner-ephemeral"].environment.RUNNER_EPHEMERAL == "1" and
  .services["runner-ephemeral"].restart == "no"
' <<< "${compose_json}" >/dev/null || {
  echo "Compose does not separate persistent and ephemeral lifecycle policies" >&2
  exit 1
}

printf 'launcher lifecycle policy tests passed\n'
