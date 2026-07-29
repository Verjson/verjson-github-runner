#!/usr/bin/env bash
set -euo pipefail

# Environment variables:
#   GITHUB_URL       — required, target org or repo URL (e.g. https://github.com/your-org or https://github.com/you/repo)
#   RUNNER_DIR       — optional, working directory containing actions-runner binaries (defaults to /home/runner/actions-runner)
#   GITHUB_PAT_FIFO  — optional, one-use mode-0600 FIFO carrying a PAT
#   RUNNER_TOKEN_CMD — optional, command that outputs a fresh registration token on (re)start
#   RUNNER_REMOVE_TOKEN_CMD — optional, command that outputs a fresh removal token on cleanup
#   RUNNER_TOKEN     — optional, static one-shot registration token (~1h expiration)
#   RUNNER_NAME      — optional, runner hostname identifier (defaults to system hostname)
#   RUNNER_LABELS    — optional, comma-separated runner labels (defaults to self-hosted,linux,x64,docker)
#   RUNNER_GROUP     — optional, org runner group name (defaults to Default)
#   RUNNER_WORKDIR   — optional, workspace folder for job runs (defaults to _work)
#   RUNNER_EPHEMERAL — optional boolean; true runs one job in this container
#   RUNNER_IMAGE     — supervisor mode only; immutable image used for fresh job containers
#   RUNNER_CHILD_MOUNT_SOCK — supervisor mode only; explicitly mount Docker into job containers
#   RUNNER_CHILD_NETWORK — supervisor mode only; metadata-denying Docker network for untrusted jobs
#   RUNNER_METADATA_DENY_ATTEST_CMD — command that attests child metadata denial
#   RUNNER_EPHEMERAL_MAX_JOBS — supervisor test/canary bound; 0 means supervise forever

normalize_ephemeral_mode() {
  local value="${RUNNER_EPHEMERAL:-false}"
  value="${value,,}"
  case "${value}" in
    1|true|yes|on) RUNNER_EPHEMERAL_ENABLED=1 ;;
    ''|0|false|no|off) RUNNER_EPHEMERAL_ENABLED=0 ;;
    *)
      echo "RUNNER_EPHEMERAL must be one of true/false, 1/0, yes/no, or on/off; got '${RUNNER_EPHEMERAL}'." >&2
      return 1 ;;
  esac
}

consume_github_pat() {
  [[ -n "${GITHUB_PAT_FIFO:-}" ]] || return 0
  [[ -p "${GITHUB_PAT_FIFO}" ]] || {
    echo "GITHUB_PAT_FIFO must name an existing one-use FIFO." >&2
    return 1
  }
  local mode
  mode="$(stat -c '%a' "${GITHUB_PAT_FIFO}")"
  [[ "${mode}" == 600 ]] || {
    echo "GITHUB_PAT_FIFO must have mode 0600." >&2
    return 1
  }
  local delivered_pat
  if ! IFS= read -r delivered_pat <"${GITHUB_PAT_FIFO}"; then
    rm -f "${GITHUB_PAT_FIFO}"
    echo "PAT delivery was interrupted." >&2
    return 1
  fi
  rm -f "${GITHUB_PAT_FIFO}"
  [[ -n "${delivered_pat}" ]] || {
    echo "PAT delivery was empty." >&2
    return 1
  }
  GITHUB_PAT="${delivered_pat}"
  unset delivered_pat
  unset GITHUB_PAT_FIFO
  export -n GITHUB_PAT 2>/dev/null || true
}

append_child_env() {
  local name="$1"
  if [[ -n "${!name:-}" ]]; then
    child_args+=(-e "${name}=${!name}")
  fi
}

proxy_for_log() {
  local proxy="$1" scheme remainder authority hostport
  if [[ "${proxy}" != *://* ]]; then
    printf '%s\n' '<invalid proxy URL>'
    return
  fi

  scheme="${proxy%%://*}"
  remainder="${proxy#*://}"
  authority="${remainder%%[/?#]*}"
  hostport="${authority##*@}"
  if [[ ! "${scheme}" =~ ^[[:alpha:]][[:alnum:]+.-]*$ ||
        -z "${hostport}" ||
        "${hostport}" =~ [[:space:]] ]]; then
    printf '%s\n' '<invalid proxy URL>'
    return
  fi

  printf '%s://%s\n' "${scheme}" "${hostport}"
}

log_configured_proxy() {
  local proxy="${HTTPS_PROXY:-${HTTP_PROXY:-${https_proxy:-${http_proxy:-}}}}"
  [[ -n "${proxy}" ]] || return 0
  printf 'Using proxy: %s%s\n' \
    "$(proxy_for_log "${proxy}")" \
    "${NO_PROXY:+ (no_proxy: ${NO_PROXY})}"
}

stop_ephemeral_child() {
  if [[ -n "${EPHEMERAL_CHILD_NAME:-}" ]]; then
    docker stop --time 10 "${EPHEMERAL_CHILD_NAME}" >/dev/null 2>&1 || true
    docker rm -f "${EPHEMERAL_CHILD_NAME}" >/dev/null 2>&1 || return 1
    if docker container inspect "${EPHEMERAL_CHILD_NAME}" >/dev/null 2>&1; then
      echo "Ephemeral child teardown failed: ${EPHEMERAL_CHILD_NAME} still exists." >&2
      return 1
    fi
    echo "EPHEMERAL_TEARDOWN child=${EPHEMERAL_CHILD_NAME} removed=true"
  fi
}

labels_include() {
  local required="${1,,}" label
  local labels=()
  IFS=',' read -r -a labels <<< "${2}"
  for label in "${labels[@]}"; do
    label="${label#"${label%%[![:space:]]*}"}"
    label="${label%"${label##*[![:space:]]}"}"
    [[ "${label,,}" == "${required}" ]] && return 0
  done
  return 1
}

validate_isolated_contract() {
  local required
  labels_include untrusted-pr "${RUNNER_LABELS:-}" || return 0
  for required in self-hosted isolated linux x64 untrusted-pr ephemeral no-host-docker; do
    labels_include "${required}" "${RUNNER_LABELS}" || {
      echo "Isolated runner contract requires label '${required}'." >&2
      return 1
    }
  done
  [[ -n "${RUNNER_GROUP:-}" && "${RUNNER_GROUP,,}" != default ]] || {
    echo "Isolated runner contract requires a non-Default RUNNER_GROUP." >&2
    return 1
  }
  [[ "${RUNNER_IMAGE:-}" =~ @sha256:[0-9a-f]{64}$ ]] || {
    echo "Isolated runner contract requires RUNNER_IMAGE pinned by immutable sha256 digest." >&2
    return 1
  }
  [[ "${RUNNER_CHILD_MOUNT_SOCK:-0}" == 0 ]] || {
    echo "Isolated runner contract forbids the host Docker socket." >&2
    return 1
  }
  [[ -n "${RUNNER_CHILD_NETWORK:-}" && ! "${RUNNER_CHILD_NETWORK}" =~ ^(bridge|host|none|default)$ ]] || {
    echo "Isolated runner contract requires a dedicated metadata-denying RUNNER_CHILD_NETWORK." >&2
    return 1
  }
  [[ -n "${RUNNER_METADATA_DENY_ATTEST_CMD:-}" ]] || {
    echo "Isolated runner contract requires RUNNER_METADATA_DENY_ATTEST_CMD." >&2
    return 1
  }
}

supervise_ephemeral() {
  : "${RUNNER_IMAGE:?Supervisor mode requires RUNNER_IMAGE}"
  : "${RUNNER_NAME:?Supervisor mode requires RUNNER_NAME}"
  : "${GITHUB_URL:?Supervisor mode requires GITHUB_URL}"
  if [[ -z "${GITHUB_PAT:-}" && -z "${RUNNER_TOKEN_CMD:-}" ]]; then
    echo "Ephemeral supervision requires GITHUB_PAT or RUNNER_TOKEN_CMD so every fresh job container can register." >&2
    return 1
  fi

  normalize_ephemeral_mode || return 1
  if [[ "${RUNNER_EPHEMERAL_ENABLED}" != 1 ]]; then
    echo "Supervisor mode requires RUNNER_EPHEMERAL=true." >&2
    return 1
  fi
  validate_isolated_contract || return 1

  local max_jobs="${RUNNER_EPHEMERAL_MAX_JOBS:-0}"
  if [[ ! "${max_jobs}" =~ ^[0-9]+$ ]]; then
    echo "RUNNER_EPHEMERAL_MAX_JOBS must be a non-negative integer." >&2
    return 1
  fi

  EPHEMERAL_CHILD_NAME="gha-${RUNNER_NAME}-job"
  trap 'stop_ephemeral_child; exit 0' SIGINT SIGTERM
  local completed=0
  while :; do
    # Remove a child left by a killed/restarted supervisor before accepting
    # another job. The exact name is derived from the configured runner name.
    docker rm -f "${EPHEMERAL_CHILD_NAME}" >/dev/null 2>&1 || true

    # Mint a short-lived, one-shot registration token in the controller. Never
    # forward the renewable PAT or token command into the untrusted job child.
    parse_github_url
    resolve_token
    if labels_include untrusted-pr "${RUNNER_LABELS:-}"; then
      eval "${RUNNER_METADATA_DENY_ATTEST_CMD}" || {
        echo "Isolated runner metadata-denial admission failed." >&2
        return 1
      }
      echo "ISOLATED_ADMISSION image=${RUNNER_IMAGE} group=${RUNNER_GROUP} labels=${RUNNER_LABELS} metadata_denied=true socket_absent=true shared_writes=false"
    fi
    child_args=(
      run --rm -i
      --name "${EPHEMERAL_CHILD_NAME}"
      --label "gha.ephemeral-job=true"
      -e "GITHUB_URL=${GITHUB_URL}"
      -e "RUNNER_NAME=${RUNNER_NAME}"
      -e "RUNNER_LABELS=${RUNNER_LABELS:-self-hosted,linux,x64}"
      -e "RUNNER_GROUP=${RUNNER_GROUP:-Default}"
      -e "RUNNER_WORKDIR=${RUNNER_WORKDIR:-_work}"
      -e "RUNNER_EPHEMERAL=1"
      -e "RUNNER_FRESH_CONTAINER=1"
      -e "RUNNER_TOKEN_STDIN=1"
    )
    if [[ -n "${RUNNER_CHILD_NETWORK:-}" ]]; then
      child_args+=(--network "${RUNNER_CHILD_NETWORK}" --add-host "metadata.google.internal:127.0.0.1")
    fi
    append_child_env HTTPS_PROXY
    append_child_env HTTP_PROXY
    append_child_env NO_PROXY
    append_child_env https_proxy
    append_child_env http_proxy
    append_child_env no_proxy
    if [[ "${RUNNER_CHILD_MOUNT_SOCK:-0}" == 1 ]]; then
      child_args+=(-v /var/run/docker.sock:/var/run/docker.sock)
    fi
    child_args+=("${RUNNER_IMAGE}")

    echo "Starting fresh ephemeral job container ${EPHEMERAL_CHILD_NAME} (generation $((completed + 1)))..."
    # Wait on a background Docker client so Bash can execute SIGINT/SIGTERM
    # traps promptly. A foreground external command defers the trap until the
    # job exits, which would leave a live child after controller shutdown.
    printf '%s\n' "${RUNNER_TOKEN}" | docker "${child_args[@]}" &
    unset RUNNER_TOKEN
    child_client_pid=$!
    if ! wait "${child_client_pid}"; then
      echo "Ephemeral job container exited unsuccessfully; recreating a clean container after backoff." >&2
      sleep 5
    fi
    docker rm -f "${EPHEMERAL_CHILD_NAME}" >/dev/null 2>&1 || true
    if docker container inspect "${EPHEMERAL_CHILD_NAME}" >/dev/null 2>&1; then
      echo "Ephemeral child teardown admission failed: ${EPHEMERAL_CHILD_NAME} still exists." >&2
      return 1
    fi
    labels_include untrusted-pr "${RUNNER_LABELS:-}" &&
      echo "ISOLATED_TEARDOWN child=${EPHEMERAL_CHILD_NAME} generation=$((completed + 1)) removed=true"
    completed=$((completed + 1))
    if [[ "${max_jobs}" -gt 0 && "${completed}" -ge "${max_jobs}" ]]; then
      echo "Ephemeral supervisor reached its ${max_jobs}-job bound."
      return 0
    fi
  done
}

runner_labels_include_ci() {
  local label
  local labels=()

  IFS=',' read -r -a labels <<< "${1}"
  for label in "${labels[@]}"; do
    label="${label#"${label%%[![:space:]]*}"}"
    label="${label%"${label##*[![:space:]]}"}"
    label="${label,,}"
    if [[ "${label}" == "ci" ]]; then
      return 0
    fi
  done

  return 1
}

run_admission_check() {
  local name="$1"
  shift

  if ! "$@"; then
    echo "CI runner admission failed: ${name} is unavailable or unhealthy." >&2
    return 1
  fi
}

run_node_24_admission_check() {
  local version

  if ! version="$(node --version)"; then
    echo "CI runner admission failed: Node.js 24 is unavailable or unhealthy." >&2
    return 1
  fi
  echo "${version}"
  if [[ ! "${version}" =~ ^v24\. ]]; then
    echo "CI runner admission failed: Node.js major 24 is required; found ${version}." >&2
    return 1
  fi
}

attest_ci_runner() {
  echo "Attesting required ci runner capabilities..."
  run_admission_check "GitHub CLI" gh --version || return 1
  run_admission_check "Docker daemon" docker version || return 1
  run_admission_check "Docker Compose" docker compose version || return 1
  run_admission_check "Docker Buildx" docker buildx version || return 1
  run_node_24_admission_check || return 1
  run_admission_check "npm" npm --version || return 1
  run_admission_check "jq" jq --version || return 1
  run_admission_check "git" git --version || return 1
  run_admission_check "bash" bash --version || return 1
  run_admission_check "curl" curl --version || return 1
  run_admission_check "grep" grep --version || return 1
  run_admission_check "sed" sed --version || return 1
  run_admission_check "awk" awk --version || return 1
  run_admission_check "find" find --version || return 1
  run_admission_check "base64" base64 --version || return 1
  run_admission_check "tar" tar --version || return 1
  run_admission_check "gzip" gzip --version || return 1
  echo "CI runner admission passed."
}

get_token() {  # $1 = registration | remove
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "${api_base}/${1}-token" | jq -r .token
}

# Resolve org-vs-repo from the URL for API calls and runner group parameters
parse_github_url() {
  path="${GITHUB_URL#https://github.com/}"
  if [[ "$path" == */* ]]; then
    api_base="https://api.github.com/repos/${path}/actions/runners"
  else
    api_base="https://api.github.com/orgs/${path}/actions/runners"
  fi

  # Runner groups only exist for org/enterprise runners, not repo-level ones.
  # Only pass --runnergroup for an org URL (path has no "/") and a non-Default group.
  group_arg=()
  if [[ "$path" != */* && -n "${RUNNER_GROUP:-}" && "${RUNNER_GROUP}" != "Default" ]]; then
    group_arg=(--runnergroup "${RUNNER_GROUP}")
  fi
}

# Token source, most-preferred first:
#   GITHUB_PAT       — mint + auto-refresh a registration token on every (re)start (physical hosts).
#   RUNNER_TOKEN_CMD — a command that prints a fresh registration token on every (re)start, so a
#                      host can inject its own minting and still get PAT-style refresh. On GCP this
#                      is the VM's App-key mint script, so no PAT/private key ever lands on the box.
#   RUNNER_REMOVE_TOKEN_CMD — optional command that prints a fresh removal token on cleanup/stop.
#   RUNNER_TOKEN     — a one-shot token (expires in ~1h; no refresh).
resolve_token() {
  if [[ -n "${GITHUB_PAT:-}" ]]; then
    RUNNER_TOKEN="$(get_token registration)"
  elif [[ -n "${RUNNER_TOKEN_CMD:-}" ]]; then
    RUNNER_TOKEN="$(eval "${RUNNER_TOKEN_CMD}")"
  fi
  : "${RUNNER_TOKEN:?Provide GITHUB_PAT (recommended), RUNNER_TOKEN_CMD, or a one-shot RUNNER_TOKEN}"
}

cleanup() {
  echo "De-registering runner..."
  if [[ -n "${GITHUB_PAT:-}" ]]; then
    ./config.sh remove --token "$(get_token remove)" || ./config.sh remove --local || true
  elif [[ -n "${RUNNER_REMOVE_TOKEN_CMD:-}" ]]; then
    ./config.sh remove --token "$(eval "${RUNNER_REMOVE_TOKEN_CMD}")" || ./config.sh remove --local || true
  else
    ./config.sh remove --local || true
  fi
  exit 0
}

main() {
  consume_github_pat || return 1
  if [[ "${1:-}" == "ci" ]]; then
    attest_ci_runner
    return $?
  fi
  if [[ "${1:-}" == "supervise" ]]; then
    supervise_ephemeral
    return $?
  fi

  : "${GITHUB_URL:?Set GITHUB_URL, e.g. https://github.com/your-org or https://github.com/you/repo}"
  cd "${RUNNER_DIR:-/home/runner/actions-runner}"

  RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
  RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,docker}"
  RUNNER_GROUP="${RUNNER_GROUP:-Default}"
  RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
  normalize_ephemeral_mode || return 1
  if [[ "${RUNNER_EPHEMERAL_ENABLED}" == 1 && "${RUNNER_FRESH_CONTAINER:-0}" != 1 ]]; then
    echo "RUNNER_EPHEMERAL requires a fresh disposable container. Use the gha supervisor or set RUNNER_FRESH_CONTAINER=1 only from an external one-job container orchestrator." >&2
    return 1
  fi

  # Advertising "ci" is a capability claim. Prove the complete contract before any
  # registration credential is minted or config.sh can make the runner schedulable.
  if runner_labels_include_ci "${RUNNER_LABELS}"; then
    attest_ci_runner || return 1
  fi

  # Proxy support: curl below and the runner itself honor HTTP(S)_PROXY / NO_PROXY from the
  # environment automatically. We just surface it in the logs when one is configured.
  log_configured_proxy

  parse_github_url
  if [[ "${RUNNER_TOKEN_STDIN:-0}" == 1 ]]; then
    if ! IFS= read -r RUNNER_TOKEN || [[ -z "${RUNNER_TOKEN}" ]]; then
      echo "Missing one-shot registration token on stdin." >&2
      return 1
    fi
  fi
  resolve_token

  trap cleanup SIGINT SIGTERM

  config_args=(
    --url "${GITHUB_URL}"
    --token "${RUNNER_TOKEN}"
    --name "${RUNNER_NAME}"
    --labels "${RUNNER_LABELS}"
    --work "${RUNNER_WORKDIR}"
    "${group_arg[@]}"
    --unattended --replace
  )
  if [[ "${RUNNER_EPHEMERAL_ENABLED}" == 1 ]]; then
    config_args+=(--ephemeral)
  fi

  ./config.sh \
    "${config_args[@]}"
  unset RUNNER_TOKEN GITHUB_PAT RUNNER_TOKEN_CMD RUNNER_REMOVE_TOKEN_CMD
  config_args=()

  # run.sh in the background + wait so the trap can fire on stop
  ./run.sh & wait $!
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
