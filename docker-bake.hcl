# BuildKit build definition for every image this repository ships.
#
# It exists so .github/workflows/image-build-check.yml can build each variant on the base
# produced in the same run with no registry in the loop. That check has to run on a
# cache-capable builder (the gha cache exporter needs buildx's docker-container driver),
# and that driver cannot resolve a tag from the local Docker image store the way the
# previous `docker build` chain did. Bake resolves `FROM ${BASE_IMAGE}` through a
# `target:base` named context instead, which keeps the ordering guarantee without pushing
# anything anywhere.
#
# Nothing here pushes or tags: publication stays in .github/workflows/publish-images.yml.

variable "PLATFORM" {
  default = "linux/amd64"
}

# publish-images.yml writes `type=gha` on every push to main and a pull request may read
# its base branch's caches, so reading the same scope is what keeps the check off a cold
# rebuild of layers that have not changed in weeks.
target "_common" {
  context    = "."
  platforms  = [PLATFORM]
  cache-from = ["type=gha"]
  cache-to   = ["type=gha,mode=max"]
}

target "base" {
  inherits   = ["_common"]
  dockerfile = "images/base.Dockerfile"
}

# Every variant below points BASE_IMAGE at the `base` target above rather than at a
# published tag, so a base change that breaks a variant fails here instead of after
# publication. That ordering is the reason the pull request check exists.
target "rust" {
  inherits   = ["_common"]
  dockerfile = "images/rust.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "node" {
  inherits   = ["_common"]
  dockerfile = "images/node.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "python" {
  inherits   = ["_common"]
  dockerfile = "images/python.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "go" {
  inherits   = ["_common"]
  dockerfile = "images/go.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "pwsh" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile.pwsh"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

# The root Dockerfile has its own FROM and its own pins, independent of
# images/base.Dockerfile, so it can break on its own and shares no context with the group
# above.
target "root" {
  inherits   = ["_common"]
  dockerfile = "Dockerfile"
}

# One solve for the whole pull request leg. BuildKit builds the base once and then fans the
# five variants out concurrently, which is why they are a group rather than one workflow
# step each: the wall clock collapses to the slowest variant instead of their sum.
group "pr-check" {
  targets = ["base", "rust", "node", "python", "go", "pwsh"]
}

# The weekly emulated leg, run with PLATFORM=linux/arm64. Only the base (gh, Node) and the
# pwsh variant (PowerShell) carry per-architecture pins; the other variants add none, so
# re-proving them under QEMU would buy nothing for a lot of minutes.
group "arch-check" {
  targets = ["base", "pwsh"]
}
