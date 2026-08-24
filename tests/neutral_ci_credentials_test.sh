#!/usr/bin/env bash
set -euo pipefail

workflow_root="$(cd "$(dirname "$0")/../.github/workflows" && pwd)"
! grep -REq 'vars\.VERJSON_|secrets\.VERJSON_(RELEASE_TOKEN|RUNNER_DEPLOY_TOKEN)' "$workflow_root"
grep -Fq 'vars.CI_LANE_PRIVILEGED' "$workflow_root/ai-privileged-merge.yml"
grep -Fq 'secrets.RELEASE_TOKEN' "$workflow_root/container-release.yml"
