#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
entrypoint="${root}/entrypoint.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
fifo="${tmp}/github-pat"
mkfifo -m 600 "${fifo}"

(
  export GITHUB_PAT_FIFO="${fifo}"
  # shellcheck disable=SC1090
  source "${entrypoint}"
  consume_github_pat
  [[ "${GITHUB_PAT}" == "test-pat" ]]
  [[ ! -e "${fifo}" ]]
) &
reader=$!
printf '%s\n' "test-pat" >"${fifo}"
wait "${reader}"

if GITHUB_PAT_FIFO="${fifo}" bash -c 'source "$1"; consume_github_pat' _ "${entrypoint}" 2>/dev/null; then
  echo "destroyed transport was replayable" >&2
  exit 1
fi

interrupted="${tmp}/interrupted"
mkfifo -m 600 "${interrupted}"
(
  exec 3>"${interrupted}"
  printf %s "partial-delivery" >&3
  exec 3>&-
) &
if GITHUB_PAT_FIFO="${interrupted}" bash -c 'source "$1"; consume_github_pat' _ "${entrypoint}" 2>/dev/null; then
  echo "interrupted delivery was accepted" >&2
  exit 1
fi
[[ ! -e "${interrupted}" ]]

for file in setup.sh setup.ps1 docker-compose.yml app/internal/dockerx/dockerx.go; do
  if grep -Eq -- '-e[[:space:]]+GITHUB_PAT=|GITHUB_PAT=.*Token' "${root}/${file}"; then
    echo "${file} contains a literal PAT docker transport" >&2
    exit 1
  fi
  grep -Eq 'GITHUB_PAT_FIFO[=:].*/run/gha-secrets/github-pat' "${root}/${file}"
done

grep -q -- '--restart no' "${root}/setup.sh"
grep -q -- '--restart no' "${root}/setup.ps1"
grep -q 'restart: "no"' "${root}/docker-compose.yml"
