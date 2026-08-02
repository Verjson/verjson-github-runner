---
date: 2026-07-29
issue: 92
title: Build the pwsh variant in the PR image check
---

`.github/workflows/image-build-check.yml` now builds `Dockerfile.pwsh` on the root image
built earlier in the same job, and `Dockerfile.pwsh` joins the workflow's `paths:` filter.
The variant landed in #91 without this wiring only because that PR would have collided
textually with #89, which rewrote the workflow.

Until now nothing built the variant before merge, so it could be broken from either side
unnoticed: by its own pins (the PowerShell release checksums) or by a root `Dockerfile`
change underneath it, since it is a thin `FROM` on that image. Pointing `BASE_IMAGE` at the
just-built `gha-runner:pr-check-root` is the same wiring the kind images use against the
base, so both failure directions surface on the PR. Fixes #92.
