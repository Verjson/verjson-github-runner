---
date: 2026-08-05
issue: 119
title: Cache and parallelise the pull request image build check
---

`image-build-check.yml` was the slowest thing this repository put in front of its own pull
requests: it read no BuildKit cache at all, so every pull request rebuilt the base image
from scratch — `apt` layers unchanged for weeks included — and it then built the four kind
images and the pwsh variant one after another in a single job. `publish-images.yml` has
been populating `type=gha` on every push to `main` the whole time; the check simply never
read it.

Both builds now go through a new `docker-bake.hcl`, and every target reads and writes a
`type=gha` cache scope of its own. The pull request leg is one bake solve over a `pr-check` group:
BuildKit builds the base once and fans the five variants out concurrently, so the wall
clock collapses toward the slowest variant instead of their sum. The weekly emulated leg is
the same shape over an `arch-check` group, but builds **cold** (`CACHE: "off"`): it exists to
catch drift a cache key cannot see — an upstream re-release under an unchanged version, or
an arm64-only package gap — and a cache hit on the `curl | sha256sum -c` layer would mean
the checksum it is there to verify never re-runs.

Two cache defects had to be fixed on both sides for any of that to pay, because adding the
cache alone measured *slower* than the uncached baseline. BuildKit keys its gha cache index
on the scope alone, so every build writing the default scope overwrote the previous index —
`publish-images.yml`'s six concurrent jobs included, which is why the cache it was
supposedly populating was never usable. Each image now reads and writes its own scope, with
the names matched on both sides so a pull request inherits what `main` published. And a
variant now exports `mode=min` rather than `mode=max`: it is a thin layer on a base that
already has a scope of its own, so `mode=max` re-exported the whole 508 MB base into each
of the five variant scopes as well. That cost more than rebuilding the variant outright
(rust: 28s to build, 53s to export) and is what pushed this repository's Actions cache past
GitHub's 10 GB quota, where entries evict each other.

Bake rather than `docker/build-push-action` because the gha cache exporter only works on
buildx's `docker-container` driver, and that driver cannot resolve a tag from the local
Docker image store the way the previous `docker build` chain did. A `target:base` named
context keeps each variant bound to the base produced in the same run — the ordering the
check exists to enforce — without a registry, an artifact round-trip or a published tag in
the loop. Nothing about what the check proves changed: it is still amd64-only,
build-only, pushes nothing and holds no registry credential, and it still fails when a
Dockerfile it builds is broken. A new `tests/image_build_check_workflow_test.sh` pins all
of that, including that each invocation names `docker-bake.hcl` explicitly — bake's file
discovery would otherwise also load `docker-compose.yml` and fail on its required
`GITHUB_PAT_DIR`. Fixes #119.
