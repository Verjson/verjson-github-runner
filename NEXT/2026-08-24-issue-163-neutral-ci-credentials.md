---
date: 2026-08-24
issue: 163
impact: patch
title: Adopt organization-neutral canonical CI credentials
---

Pinned generated CI contracts now consume neutral lane variables and mint the
repository-bound Contents-only Release App token for terminal Git/GitHub Release
writes, while job-scoped package authority handles GHCR promotion and retention.
