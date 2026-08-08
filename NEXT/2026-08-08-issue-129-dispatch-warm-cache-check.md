---
date: 2026-08-08
issue: 129
title: Allow on-demand warm-cache image checks
---

- Add an explicit `amd64` workflow-dispatch mode so cache retention can be measured without manufacturing a pull request.
- Preserve the cold arm64 verification as the default on-demand build.
