#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_URL:?Set GITHUB_URL, e.g. https://github.com/your-org or https://github.com/you/repo}"
cd /home/runner/actions-runner

# Proxy support: curl below and the runner itself honor HTTP(S)_PROXY / NO_PROXY from the
# environment automatically. We just surface it in the logs when one is configured.
if [[ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}" ]]; then
  echo "Using proxy: ${HTTPS_PROXY:-${HTTP_PROXY}}${NO_PROXY:+ (no_proxy: ${NO_PROXY})}"
fi

# Resolve org-vs-repo from the URL for the API calls
path="${GITHUB_URL#https://github.com/}"
if [[ "$path" == */* ]]; then
  api_base="https://api.github.com/repos/${path}/actions/runners"
else
  api_base="https://api.github.com/orgs/${path}/actions/runners"
fi

get_token() {  # $1 = registration | remove
  curl -fsSL -X POST \
    -H "Authorization: Bearer ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "${api_base}/${1}-token" | jq -r .token
}

# Token source, most-preferred first:
#   GITHUB_PAT       — mint + auto-refresh a registration token on every (re)start (physical hosts).
#   RUNNER_TOKEN_CMD — a command that prints a fresh registration token on every (re)start, so a
#                      host can inject its own minting and still get PAT-style refresh. On GCP this
#                      is the VM's App-key mint script, so no PAT/private key ever lands on the box.
#   RUNNER_TOKEN     — a one-shot token (expires in ~1h; no refresh).
if [[ -n "${GITHUB_PAT:-}" ]]; then
  RUNNER_TOKEN="$(get_token registration)"
elif [[ -n "${RUNNER_TOKEN_CMD:-}" ]]; then
  RUNNER_TOKEN="$(eval "${RUNNER_TOKEN_CMD}")"
fi
: "${RUNNER_TOKEN:?Provide GITHUB_PAT (recommended), RUNNER_TOKEN_CMD, or a one-shot RUNNER_TOKEN}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,docker}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"

# Runner groups only exist for org/enterprise runners, not repo-level ones.
# Only pass --runnergroup for an org URL (path has no "/") and a non-Default group.
group_arg=()
if [[ "$path" != */* && -n "${RUNNER_GROUP}" && "${RUNNER_GROUP}" != "Default" ]]; then
  group_arg=(--runnergroup "${RUNNER_GROUP}")
fi

cleanup() {
  echo "De-registering runner..."
  if [[ -n "${GITHUB_PAT:-}" ]]; then
    ./config.sh remove --token "$(get_token remove)" || ./config.sh remove --local || true
  else
    ./config.sh remove --local || true
  fi
  exit 0
}
trap cleanup SIGINT SIGTERM

./config.sh \
  --url "${GITHUB_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --work "${RUNNER_WORKDIR}" \
  "${group_arg[@]}" \
  --unattended --replace ${RUNNER_EPHEMERAL:+--ephemeral}

# run.sh in the background + wait so the trap can fire on stop
./run.sh & wait $!
