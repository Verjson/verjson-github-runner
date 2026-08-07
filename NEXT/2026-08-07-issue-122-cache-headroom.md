---
date: 2026-08-07
issue: 122
title: Stop pull requests duplicating the image cache
---

Pull request image checks now read the default branch's BuildKit cache without exporting duplicate branch-scoped copies, preserving cache headroom for the published base and kind images.

The measured inventory was 10.73 GB across 251 entries: 6.40 GB on `main`, 4.25 GB retained by merged PR #120, and 0.07 GB on two other pull request refs. `scripts/cache-inventory.sh Verjson/verjson-github-runner` provides a read-only, paginated follow-up measurement. Existing branch caches are left for GitHub's normal expiry; this change grants no write permission and performs no remote deletion.

Issue #122 remains open until several post-merge main publications stay below 10 GB and a pull request opened at least a day later proves the base remains warm and beats the 2m05s baseline.
