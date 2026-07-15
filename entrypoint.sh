#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_URL:?Set GITHUB_URL, e.g. https://github.com/your-org or https://github.com/you/repo}"
cd /home/runner/actions-runner

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

# Prefer a PAT (auto-refreshes tokens on every start/stop). Fallback: one-shot RUNNER_TOKEN.
if [[ -n "${GITHUB_PAT:-}" ]]; then
  RUNNER_TOKEN="$(get_token registration)"
fi
: "${RUNNER_TOKEN:?Provide GITHUB_PAT (recommended) or a one-shot RUNNER_TOKEN}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,docker}"

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
  --work _work \
  --unattended --replace ${RUNNER_EPHEMERAL:+--ephemeral}

# run.sh in the background + wait so the trap can fire on stop
./run.sh & wait $!
