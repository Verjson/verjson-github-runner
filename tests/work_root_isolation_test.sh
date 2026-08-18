#!/usr/bin/env bash
set -euo pipefail

# Reproduction for issue #155: two runner processes pointed at the same absolute --work
# directory let one job's actions/checkout corrupt a concurrent job's index/worktree.
# This proves claim_work_root refuses the collision before either process can touch git
# state, and that two properly isolated work roots can run overlapping checkouts of
# different refs without interference.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "${sandbox}"' EXIT

# A source repo with two refs, mirroring PR #855 (adds only-on-855) and PR #861 (adds
# only-on-861 and removes only-on-855) from the original incident.
src="${sandbox}/src.git"
git init -q "${src}"
git -C "${src}" config user.email test@example.com
git -C "${src}" config user.name test
echo base > "${src}/base.txt"
git -C "${src}" add base.txt
git -C "${src}" commit -q -m base

echo 855 > "${src}/only-on-855.txt"
git -C "${src}" add only-on-855.txt
git -C "${src}" commit -q -m pr-855
ref_855="$(git -C "${src}" rev-parse HEAD)"

git -C "${src}" rm -q only-on-855.txt
echo 861 > "${src}/only-on-861.txt"
git -C "${src}" add only-on-861.txt
git -C "${src}" commit -q -m pr-861
ref_861="$(git -C "${src}" rev-parse HEAD)"

# --- Case 1: two runner processes share one work root -----------------------------
shared_dir="${sandbox}/shared-runner-dir"
mkdir -p "${shared_dir}"

(
  cd "${shared_dir}"
  # shellcheck source=../entrypoint.sh
  source "${root}/entrypoint.sh"
  RUNNER_NAME="gha-general-10"
  RUNNER_WORKDIR="_work"
  claim_work_root
  git clone -q "${src}" _work/checkout
  git -C _work/checkout checkout -q "${ref_855}"
  # Hold the claim (and the checkout) open while job 2 tries to collide.
  sleep 2
) &
job1_pid=$!

# Give job 1 time to claim the root and start its checkout before job 2 races it.
for _ in $(seq 1 50); do
  [[ -f "${shared_dir}/_work/.gha-work-root.lock" ]] && break
  sleep 0.1
done

set +e
job2_output="$(
  cd "${shared_dir}"
  # shellcheck source=../entrypoint.sh
  source "${root}/entrypoint.sh"
  RUNNER_NAME="gha-general-11"
  RUNNER_WORKDIR="_work"
  claim_work_root 2>&1
)"
job2_status=$?
set -e

wait "${job1_pid}"

if [[ ${job2_status} -eq 0 ]]; then
  echo "job 2 was admitted onto a work root job 1 already held" >&2
  exit 1
fi
grep -qF "already claimed by another active runner process" <<< "${job2_output}"
grep -qF "gha-general-10" <<< "${job2_output}"

# Job 1's checkout is exactly ref 855, untouched by a job 2 that never started.
[[ "$(git -C "${shared_dir}/_work/checkout" rev-parse HEAD)" == "${ref_855}" ]]
[[ -f "${shared_dir}/_work/checkout/only-on-855.txt" ]]
[[ ! -f "${shared_dir}/_work/checkout/only-on-861.txt" ]]
[[ -z "$(git -C "${shared_dir}/_work/checkout" status --porcelain)" ]]

echo "Case 1 passed: a colliding second runner is refused before touching the checkout."

# --- Case 2: two runner processes, two distinct work roots ------------------------
dir_a="${sandbox}/runner-a"
dir_b="${sandbox}/runner-b"
mkdir -p "${dir_a}" "${dir_b}"

(
  cd "${dir_a}"
  # shellcheck source=../entrypoint.sh
  source "${root}/entrypoint.sh"
  RUNNER_NAME="gha-general-10"
  RUNNER_WORKDIR="_work"
  claim_work_root
  git clone -q "${src}" _work/checkout
  git -C _work/checkout checkout -q "${ref_855}"
) &
pid_a=$!

(
  cd "${dir_b}"
  # shellcheck source=../entrypoint.sh
  source "${root}/entrypoint.sh"
  RUNNER_NAME="gha-general-11"
  RUNNER_WORKDIR="_work"
  claim_work_root
  git clone -q "${src}" _work/checkout
  git -C _work/checkout checkout -q "${ref_861}"
) &
pid_b=$!

wait "${pid_a}"
wait "${pid_b}"

[[ "$(git -C "${dir_a}/_work/checkout" rev-parse HEAD)" == "${ref_855}" ]]
[[ -f "${dir_a}/_work/checkout/only-on-855.txt" ]]
[[ "$(git -C "${dir_b}/_work/checkout" rev-parse HEAD)" == "${ref_861}" ]]
[[ -f "${dir_b}/_work/checkout/only-on-861.txt" ]]

echo "Case 2 passed: isolated work roots run overlapping checkouts of different refs cleanly."
