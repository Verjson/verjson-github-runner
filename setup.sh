#!/usr/bin/env bash
#
# Interactive setup for one or more Dockerized GitHub Actions self-hosted runners.
# Prompts for the details, builds the image, and launches each runner as an
# background service. One-use credential delivery intentionally requires the
# operator to re-run setup after a host or container restart.
#
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="gha-runner:local"
transport_dir=""
delivery_container=""

case "$(uname -m)" in
  x86_64|amd64) ARCH_LABEL="x64" ;;
  aarch64|arm64) ARCH_LABEL="ARM64" ;;
  *) echo "Unsupported runner architecture: $(uname -m)." >&2; exit 1 ;;
esac

cleanup_transport() {
  [[ -z "${delivery_container}" ]] || docker rm -f "${delivery_container}" >/dev/null 2>&1 || true
  [[ -z "${transport_dir}" ]] || rm -rf "${transport_dir}"
}
trap cleanup_transport EXIT INT TERM

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
ask()  { local p="$1" d="${2:-}" v; if [ -n "$d" ]; then read -rp "$p [$d]: " v; echo "${v:-$d}"; else read -rp "$p: " v; echo "$v"; fi; }

bold "=== GitHub self-hosted runner setup ==="

GITHUB_URL="$(ask 'GitHub URL (org e.g. https://github.com/Verjson, or repo URL)')"
[ -z "$GITHUB_URL" ] && { echo "GitHub URL is required."; exit 1; }

read -rsp "GitHub PAT (input hidden): " GITHUB_PAT; echo
[ -z "$GITHUB_PAT" ] && { echo "A PAT is required (org: admin:org  /  repo: repo)."; exit 1; }

NAMES_INPUT="$(ask 'Runner name(s), comma-separated' 'ci-runner-01')"
LABELS="$(ask 'Labels (comma-separated)' "self-hosted,linux,${ARCH_LABEL},docker")"
RUNNER_GROUP="$(ask 'Runner group (org runners only; Default for repo)' 'Default')"
RUNNER_WORKDIR="$(ask 'Work folder' '_work')"

bold "Building image ($IMAGE)..."
docker build -t "$IMAGE" .

IFS=',' read -ra NAMES <<< "$NAMES_INPUT"
for raw in "${NAMES[@]}"; do
  name="$(echo "$raw" | xargs)"   # trim whitespace
  [ -z "$name" ] && continue
  container="gha-${name}"
  delivery_container="${container}"
  bold "Starting runner '${name}' (container: ${container})"
  docker rm -f "$container" >/dev/null 2>&1 || true
  transport_dir="$(mktemp -d)"
  chmod 700 "$transport_dir"
  pat_fifo="${transport_dir}/github-pat"
  mkfifo -m 600 "$pat_fifo"
  docker run -d \
    --name "$container" \
    --restart no \
    --mount "type=bind,src=${transport_dir},dst=/run/gha-secrets" \
    -e GITHUB_URL="$GITHUB_URL" \
    -e GITHUB_PAT_FIFO=/run/gha-secrets/github-pat \
    -e RUNNER_NAME="$name" \
    -e RUNNER_LABELS="$LABELS" \
    -e RUNNER_GROUP="$RUNNER_GROUP" \
    -e RUNNER_WORKDIR="$RUNNER_WORKDIR" \
    "$IMAGE" >/dev/null
  printf '%s\n' "$GITHUB_PAT" >"$pat_fifo"
  rm -rf "$transport_dir"
  transport_dir=""
  delivery_container=""
done
unset GITHUB_PAT

echo
bold "Runners are up:"
docker ps --filter "name=gha-" --format "table {{.Names}}\t{{.Status}}"
echo
echo "Follow logs:   docker logs -f gha-<name>   (wait for 'Listening for Jobs')"
echo "Stop one:      docker rm -f gha-<name>      (leaves an offline entry unless de-registered)"
echo "Restart one:   re-run setup; the one-use credential transport intentionally disables Docker auto-restart"
echo "Target it in a workflow:  runs-on: [ ${LABELS//,/, } ]"
