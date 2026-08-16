#!/usr/bin/env bash
# shellcheck disable=SC2016 # Docker and GitHub expressions below are intentional literals.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${root}/container-candidate.json"
candidate="${root}/.github/workflows/container-candidate.yml"
release="${root}/.github/workflows/container-release.yml"
contract_ref="4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9"
changelog_sha256="9d2866cd11b600fcd8cfa160f9599b4158f6b18f1b538aa6baf450d0b4b7666b"

fail() {
  echo "container release workflow contract: $*" >&2
  exit 1
}

[[ ! -e "${root}/.github/workflows/publish-images.yml" ]] \
  || fail "legacy merge-driven stable publication still exists"

for workflow in "${root}"/.github/workflows/*.yml; do
  if grep -q '^  packages: write$' "${workflow}" \
    && [[ "${workflow}" != "${candidate}" ]]; then
    fail "competing package publication permission remains in ${workflow}"
  fi
done

printf '%s  %s\n' "${changelog_sha256}" "${root}/scripts/changelog.py" \
  | sha256sum --check --strict >/dev/null \
  || fail "release changelog engine differs from the pinned canonical implementation"

python3 - "${config}" "${contract_ref}" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1], encoding="utf-8"))
assert config["schemaVersion"] == 1
assert config["repository"] == "Verjson/verjson-github-runner"
assert config["registryNamespace"] == "ghcr.io/verjson"
assert config["nextStableVersion"] == "0.2.0"
assert config.get("privateNodePackages", []) == []

expected = {
    "base": ("ghcr.io/verjson/gha-runner", "images/base.Dockerfile", None),
    "rust": ("ghcr.io/verjson/gha-runner-rust", "images/rust.Dockerfile", "base"),
    "node": ("ghcr.io/verjson/gha-runner-node", "images/node.Dockerfile", "base"),
    "python": ("ghcr.io/verjson/gha-runner-python", "images/python.Dockerfile", "base"),
    "go": ("ghcr.io/verjson/gha-runner-go", "images/go.Dockerfile", "base"),
    "pwsh": ("ghcr.io/verjson/gha-runner-pwsh", "Dockerfile.pwsh", "base"),
}
images = {image["variant"]: image for image in config["images"]}
assert images.keys() == expected.keys()
assert len({image["repository"] for image in images.values()}) == len(images)

builder = "Verjson/.github/.github/workflows/container-candidate.yml@" + sys.argv[2]
platforms = [
    {"os": "linux", "architecture": "amd64"},
    {"os": "linux", "architecture": "arm64"},
]
for variant, (repository, dockerfile, base_variant) in expected.items():
    image = images[variant]
    assert image["repository"] == repository
    assert image["context"] == "."
    assert image["file"] == dockerfile
    assert image.get("baseVariant") == base_variant
    assert image["platforms"] == platforms
    assert image["provenance"] == {
        "predicateType": "https://slsa.dev/provenance/v1",
        "builderIdentity": builder,
    }
PY

for dockerfile in \
  images/rust.Dockerfile images/node.Dockerfile images/python.Dockerfile \
  images/go.Dockerfile Dockerfile.pwsh; do
  grep -qx 'ARG VERJSON_BASE_IMAGE=ghcr.io/verjson/gha-runner:base' "${root}/${dockerfile}" \
    || fail "${dockerfile} does not default standalone builds to the public base"
  grep -qx 'FROM ${VERJSON_BASE_IMAGE}' "${root}/${dockerfile}" \
    || fail "${dockerfile} does not build from the canonical same-run base digest"
done

grep -qx '  push:' "${candidate}" || fail "main does not publish immutable candidates"
grep -qx '    branches: \[main\]' "${candidate}" || fail "candidate push is not limited to main"
grep -qx '  pull_request:' "${candidate}" || fail "pull requests do not exercise candidate builds"
! grep -Eq '(^|[^[:alnum:]_-])(latest|stable):|:[0-9]+\.[0-9]+\.[0-9]+' "${candidate}" \
  || fail "candidate caller contains a stable alias"
grep -Fq "container-candidate.yml@${contract_ref}" "${candidate}" \
  || fail "candidate caller does not use the reviewed canonical contract"

grep -qx '  workflow_dispatch:' "${release}" || fail "stable promotion is not explicitly dispatched"
! grep -Eq '^  (push|pull_request):' "${release}" \
  || fail "stable promotion is reachable from merge or pull request"
! grep -Eq 'docker (build|bake)|build-push-action|Dockerfile' "${release}" \
  || fail "release caller rebuilds instead of promoting retained digests"
grep -Fq "container-release.yml@${contract_ref}" "${release}" \
  || fail "release caller does not use the reviewed canonical contract"

echo "container release workflow tests passed"
