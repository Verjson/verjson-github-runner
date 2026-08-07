#!/usr/bin/env bash
set -euo pipefail

repository="${1:-${GITHUB_REPOSITORY:-}}"
[[ "${repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "usage: $0 OWNER/REPOSITORY" >&2
  exit 2
}

gh api -X GET --paginate "repos/${repository}/actions/caches" -f per_page=100 |
  jq -sr '
    [.[].actions_caches[]] as $caches
    | [
        ["TOTAL", ($caches | map(.size_in_bytes) | add // 0), ($caches | length)],
        (
          $caches
          | group_by(.ref)
          | map([.[0].ref, (map(.size_in_bytes) | add), length])
          | sort_by(.[1])
          | reverse[]
        )
      ]
    | .[]
    | @tsv
  ' |
  awk -F '\t' '{
    printf "%s\t%s\t%.2f GB\t%s\n", $1, $2, $2 / 1000000000, $3
  }'
