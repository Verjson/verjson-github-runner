#!/usr/bin/env bash
# shellcheck disable=SC2016 # GitHub expressions below are intentional literals.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${1:-${root}/.github/workflows/image-build-check.yml}"
bakefile="${2:-${root}/docker-bake.hcl}"

fail() {
  echo "image-build-check contract: $*" >&2
  exit 1
}

hcl_block() {
  local name="$1"
  awk -v name="${name}" '
    $0 ~ "^target \"" name "\" \\{" { capture = 1; next }
    capture && /^\}/ { exit }
    capture { print }
  ' "${bakefile}"
}

hcl_target_names() {
  awk '/^target "/ { sub(/^target "/, ""); sub(/".*$/, ""); print }' "${bakefile}"
}

[[ -f "${workflow}" ]] || fail "workflow not found: ${workflow}"
[[ -f "${bakefile}" ]] || fail "bake definition not found: ${bakefile}"

# Every image the check builds must read from and write to the same BuildKit layer cache
# that publish-images.yml populates on every push to main. Without it the check rebuilds
# the base image from scratch for every derived image on every pull request.
bakefile_text="$(<"${bakefile}")"
[[ "${bakefile_text}" == *'result = ["type=gha,scope=${scope}"]'* ]] \
  || fail "cache reads are not gha cache reads"
[[ "${bakefile_text}" == *'result = ["type=gha,mode=max,scope=${scope}"]'* ]] \
  || fail "root image cache writes are not gha mode=max cache writes"
[[ "${bakefile_text}" == *'result = ["type=gha,mode=min,scope=${scope}"]'* ]] \
  || fail "variant cache writes are not gha mode=min cache writes"

# One scope per image. BuildKit keys its gha cache index on the scope alone, so builds
# sharing the default scope overwrite each other's index: seven builds against one scope
# left a warm re-run of an unchanged commit with zero layer hits.
targets="$(hcl_target_names)"
[[ -n "${targets}" ]] || fail "no bake targets found in ${bakefile}"
while IFS= read -r target; do
  [[ "${target}" == "_common" ]] && continue
  block="$(hcl_block "${target}")"
  [[ "${block}" == *'inherits   = ["_common"]'* ]] \
    || fail "target '${target}' does not inherit the shared build settings"
  [[ "${block}" == *"cache-from = cache_from(\"${target}\")"* ]] \
    || fail "target '${target}' does not read its own cache scope"
  case "${target}" in
    # A variant is a thin layer whose parent already has a scope of its own. Exporting it
    # mode=max re-exports the whole 508 MB base into the variant's scope as well, which
    # cost more than rebuilding the variant and is what pushed the repository past its
    # 10 GB cache quota into self-eviction.
    base | root)
      [[ "${block}" == *"cache-to   = cache_to_full(\"${target}\")"* ]] \
        || fail "root image '${target}' does not export its full layer cache" ;;
    *)
      [[ "${block}" == *"cache-to   = cache_to_thin(\"${target}\")"* ]] \
        || fail "variant '${target}' must not re-export its base's layers" ;;
  esac
done <<<"${targets}"

# A raw `docker build` uses the default builder, which cannot export to the gha cache,
# so any surviving invocation would silently reintroduce the cold rebuild.
raw_builds="$(grep -Ec '(^|[^-])docker build ' "${workflow}" || true)"
[[ "${raw_builds}" == "0" ]] \
  || fail "workflow still shells out to uncached 'docker build' (${raw_builds} occurrence(s))"

# The four kinds are siblings — each a thin layer on the same base — so they belong in one
# BuildKit solve that runs them concurrently, not in one workflow step after another.
pr_check_group="$(awk '
  /^group "pr-check" \{/ { capture = 1; next }
  capture && /^\}/ { exit }
  capture { print }
' "${bakefile}")"
for target in base rust node python go pwsh; do
  [[ "${pr_check_group}" == *"\"${target}\""* ]] \
    || fail "pull request group does not build the '${target}' image"
done

pr_bake_steps="$(awk '
  /^  base-and-kinds:/ { capture = 1; next }
  capture && /^  [a-z]/ { exit }
  capture && /targets: / { print }
' "${workflow}")"
[[ "${pr_bake_steps}" == "          targets: pr-check" ]] \
  || fail "pull request leg must build every image in a single concurrent bake invocation, found: ${pr_bake_steps:-<none>}"

# Concurrency must not cost the ordering the check exists for: each variant still resolves
# its base from the target built in this same run, never from a published tag.
for target in rust node python go pwsh; do
  block="$(hcl_block "${target}")"
  [[ "${block}" == *'contexts   = { base = "target:base" }'* ]] \
    || fail "target '${target}' does not build on the base produced in the same run"
  [[ "${block}" == *'args       = { BASE_IMAGE = "base" }'* ]] \
    || fail "target '${target}' does not point BASE_IMAGE at that same-run base"
done
if grep -Fq 'ghcr.io' "${bakefile}"; then
  fail "bake definition must not resolve any image from a published registry tag"
fi

# The bake definition is now a build input: editing it can change what every image is
# built from, so a pull request that touches it has to re-run this check.
paths="$(awk '
  /^    paths:$/ { capture = 1; next }
  capture && /^    [^ -]/ { exit }
  capture { print }
' "${workflow}")"
[[ "${paths}" == *"      - docker-bake.hcl"* ]] \
  || fail "path filter does not re-run the check when the bake definition changes"

# The emulated arm64 leg builds pwsh on base too, so it is the same one-solve shape rather
# than two invocations that each have to materialise the base.
arm64_bake_steps="$(awk '
  /^  base-and-pwsh-arm64:/ { capture = 1; next }
  capture && /^  [a-z]/ { exit }
  capture && /targets: / { print }
' "${workflow}")"
[[ "${arm64_bake_steps}" == "          targets: arch-check" ]] \
  || fail "arm64 leg must build in a single bake invocation, found: ${arm64_bake_steps:-<none>}"
arch_check_group="$(awk '
  /^group "arch-check" \{/ { capture = 1; next }
  capture && /^\}/ { exit }
  capture { print }
' "${bakefile}")"
for target in base pwsh; do
  [[ "${arch_check_group}" == *"\"${target}\""* ]] \
    || fail "arm64 group does not build the '${target}' image"
done
[[ "$(grep -Fc 'PLATFORM: linux/arm64' "${workflow}")" == "1" ]] \
  || fail "arm64 leg must override the build platform exactly once"

# Build-only is a property of this check, not an accident of how it was written: it holds
# no registry credential and touches no tag, so it can run on a fork pull request.
permissions="$(awk '
  /^permissions:$/ { capture = 1; next }
  capture && /^[^ ]/ { exit }
  capture && /^  [a-z][a-z-]*: / { print }
' "${workflow}")"
[[ "${permissions}" == "  contents: read" ]] \
  || fail "check must stay read-only, found permissions: ${permissions}"
for forbidden in 'docker/login-action' 'push: true' 'ghcr.io' 'secrets.'; do
  if grep -Fq -- "${forbidden}" "${workflow}"; then
    fail "build-only check must not reference '${forbidden}'"
  fi
done

# Bake's default file discovery also picks up the repo's docker-compose.yml, whose runner
# service requires GITHUB_PAT_DIR, so every invocation must name its definition explicitly
# or the check fails on interpolation before it builds anything.
bake_steps="$(grep -Fc -- 'uses: docker/bake-action@' "${workflow}" || true)"
[[ "${bake_steps}" -gt 0 ]] || fail "no bake build steps found"
[[ "$(grep -Fc 'files: docker-bake.hcl' "${workflow}")" == "${bake_steps}" ]] \
  || fail "every bake step must name docker-bake.hcl instead of relying on file discovery"

# bake-action defaults its source to the remote git context, which would silently ignore
# the checkout and build a ref fetched from GitHub rather than the tree under test.
[[ "$(grep -Fc 'source: .' "${workflow}")" == "${bake_steps}" ]] \
  || fail "every bake step must build the checked-out workspace, not a remote git context"

while IFS= read -r action; do
  [[ "${action}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$ ]] \
    || fail "action is not pinned to an immutable SHA: ${action}"
done < <(
  awk '/uses: / {
    sub(/^.*uses: /, "")
    sub(/[[:space:]]+#.*$/, "")
    print
  }' "${workflow}"
)
