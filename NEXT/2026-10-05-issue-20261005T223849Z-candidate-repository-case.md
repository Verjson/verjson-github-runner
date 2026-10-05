---
date: 2026-10-05
id: 20261005T223849Z
title: Align candidate repository case with GitHub identity
impact: patch
---

Align the container candidate configuration with GitHub's reported repository
name so the canonical validator accepts pull request builds. Invoke the pinned
changelog cache script with Bash directly so the Ubuntu 26.04 arm64 build does
not fail its `env` executable-name check under QEMU.
