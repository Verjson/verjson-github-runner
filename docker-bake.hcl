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

# One cache scope per image, never the default shared one. BuildKit keys its gha cache
# index on the scope, so concurrent builds sharing a scope overwrite each other's index:
# with seven builds on the default scope a warm re-run of an unchanged commit got zero
# layer hits. The scope names match the ones publish-images.yml writes on every push to
# main, which is the cache a pull request inherits from its base branch.
function "cache_from" {
  params = [scope]
  result = ["type=gha,scope=${scope}"]
}

function "cache_to_full" {
  params = [scope]
  result = ["type=gha,mode=max,scope=${scope}"]
}

# A variant is a thin layer on a base that already has a cache scope of its own. Exporting
# it mode=max re-exports the whole 508 MB base into the variant's scope too, which measured
# slower than rebuilding the variant outright (rust: 28s to build, 53s to export) and is
# what pushed this repository past GitHub's 10 GB cache quota into evicting its own entries.
function "cache_to_thin" {
  params = [scope]
  result = ["type=gha,mode=min,scope=${scope}"]
}

target "_common" {
  context   = "."
  platforms = [PLATFORM]
}

target "base" {
  inherits   = ["_common"]
  cache-from = cache_from("base")
  cache-to   = cache_to_full("base")
  dockerfile = "images/base.Dockerfile"
}

# Every variant below points BASE_IMAGE at the `base` target above rather than at a
# published tag, so a base change that breaks a variant fails here instead of after
# publication. That ordering is the reason the pull request check exists.
target "rust" {
  inherits   = ["_common"]
  cache-from = cache_from("rust")
  cache-to   = cache_to_thin("rust")
  dockerfile = "images/rust.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "node" {
  inherits   = ["_common"]
  cache-from = cache_from("node")
  cache-to   = cache_to_thin("node")
  dockerfile = "images/node.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "python" {
  inherits   = ["_common"]
  cache-from = cache_from("python")
  cache-to   = cache_to_thin("python")
  dockerfile = "images/python.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "go" {
  inherits   = ["_common"]
  cache-from = cache_from("go")
  cache-to   = cache_to_thin("go")
  dockerfile = "images/go.Dockerfile"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

target "pwsh" {
  inherits   = ["_common"]
  cache-from = cache_from("pwsh")
  cache-to   = cache_to_thin("pwsh")
  dockerfile = "Dockerfile.pwsh"
  contexts   = { base = "target:base" }
  args       = { BASE_IMAGE = "base" }
}

# The root Dockerfile has its own FROM and its own pins, independent of
# images/base.Dockerfile, so it can break on its own and shares no context with the group
# above.
target "root" {
  inherits   = ["_common"]
  cache-from = cache_from("root")
  cache-to   = cache_to_full("root")
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
