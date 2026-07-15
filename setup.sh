#!/usr/bin/env bash
#
# Interactive setup for one or more Dockerized GitHub Actions self-hosted runners.
# Prompts for the details, builds the image, and launches each runner as an
# auto-restarting background service (Docker `--restart unless-stopped`, so they
# also come back after a reboot as long as the Docker daemon is enabled).
#
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="gha-runner:local"

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ask()  { local p="$1" d="${2:-}" v; if [ -n "$d" ]; then read -rp "$p [$d]: " v; echo "${v:-$d}"; else read -rp "$p: " v; echo "$v"; fi; }

bold "=== GitHub self-hosted runner setup ==="

GITHUB_URL="$(ask 'GitHub URL (org e.g. https://github.com/Verjson, or repo URL)')"
[ -z "$GITHUB_URL" ] && { echo "GitHub URL is required."; exit 1; }

read -rsp "GitHub PAT (input hidden): " GITHUB_PAT; echo
[ -z "$GITHUB_PAT" ] && { echo "A PAT is required (org: admin:org  /  repo: repo)."; exit 1; }

NAMES_INPUT="$(ask 'Runner name(s), comma-separated' 'ci-runner-01')"
LABELS="$(ask 'Labels (comma-separated)' 'self-hosted,linux,x64,docker')"
RUNNER_GROUP="$(ask 'Runner group (org runners only; Default for repo)' 'Default')"
RUNNER_WORKDIR="$(ask 'Work folder' '_work')"

bold "Building image ($IMAGE)..."
docker build -t "$IMAGE" .

IFS=',' read -ra NAMES <<< "$NAMES_INPUT"
for raw in "${NAMES[@]}"; do
  name="$(echo "$raw" | xargs)"   # trim whitespace
  [ -z "$name" ] && continue
  container="gha-${name}"
  bold "Starting runner '${name}' (container: ${container})"
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker run -d \
    --name "$container" \
    --restart unless-stopped \
    -e GITHUB_URL="$GITHUB_URL" \
    -e GITHUB_PAT="$GITHUB_PAT" \
    -e RUNNER_NAME="$name" \
    -e RUNNER_LABELS="$LABELS" \
    -e RUNNER_GROUP="$RUNNER_GROUP" \
    -e RUNNER_WORKDIR="$RUNNER_WORKDIR" \
    "$IMAGE" >/dev/null
done

echo
bold "Runners are up:"
docker ps --filter "name=gha-" --format "table {{.Names}}\t{{.Status}}"
echo
echo "Follow logs:   docker logs -f gha-<name>   (wait for 'Listening for Jobs')"
echo "Stop one:      docker rm -f gha-<name>      (leaves an offline entry unless de-registered)"
echo "Target it in a workflow:  runs-on: [ ${LABELS//,/, } ]"
