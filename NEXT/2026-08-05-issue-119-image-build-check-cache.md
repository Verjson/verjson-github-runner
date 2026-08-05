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

Both builds now go through a new `docker-bake.hcl`, and every target reads `type=gha` and
writes `type=gha,mode=max`. The pull request leg is one bake solve over a `pr-check` group:
BuildKit builds the base once and fans the five variants out concurrently, so the wall
clock collapses toward the slowest variant instead of their sum. The weekly emulated leg is
the same shape over an `arch-check` group.

Each image also gets its own cache scope, here and in `publish-images.yml`. BuildKit keys
its gha cache index on the scope alone, so the builds sharing the default scope had been
overwriting each other's index — the publication workflow's six concurrent jobs included.
Adding the cache without that fix measured *slower*, not faster: a warm re-run of an
unchanged commit got zero layer hits and still paid the export. The scope names match on
both sides so a pull request inherits what `main` published.

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
