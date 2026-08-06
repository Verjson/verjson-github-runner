---
date: 2026-07-29
issue: 87
title: Catch arm64 image breakage on a schedule, not on main
summary: The image build check now also runs on a weekly schedule and on demand, adding a `base-arm64` job that sets up QEMU and builds `images/base.Dockerfile` for `linux/arm64`, build-only. The per-arch `GH_SHA256_ARM64` and `NODE_SHA256_ARM64` pins had never been exercised before merge, so an upstream re-release or an arm64-only package gap first surfaced when `publish-images.yml` built the real multi-arch image on `main`. Emulated arm64 is far too slow to gate every pull request, so it is proven periodically instead, and the amd64 jobs are gated to `pull_request` so the cron runs only the arm64 leg.
---

`image-build-check.yml` builds amd64 only, so the arch-specific half of
`images/base.Dockerfile` — the per-arch `GH_SHA256_ARM64` / `NODE_SHA256_ARM64` pins — was
never exercised before merge. An upstream re-release that changes an arm64 tarball, or an
arm64-only package gap, first surfaced when `publish-images.yml` built the real multi-arch
image on `main`, which is exactly the "broken after it ships" failure the PR check was
added to remove.

The workflow now also runs on `schedule` (Mondays 07:23 UTC) and `workflow_dispatch`, with
a `base-arm64` job that sets up QEMU — same pinned `docker/setup-qemu-action` as
`publish-images.yml` — and builds the base image for `linux/arm64`, build-only. Emulated
arm64 is far too slow to gate every PR, so it is periodic and on-demand instead; the
amd64 `base-and-kinds` and `root` jobs are gated to `pull_request` so the cron runs only
the arm64 leg and does not re-prove what `main` already builds natively. Only the base is
built for arm64: the kind images add no per-arch pins of their own, so the base is where
the whole gap lives. Fixes #87.
