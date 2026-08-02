---
date: 2026-07-28
issue: 43
title: Deliver the runner PAT through a one-use FIFO
---

Replace inspectable Docker `GITHUB_PAT` configuration with a one-use,
mode-0600 host FIFO consumed into non-exported supervisor memory; disable
unsafe automatic restart and require explicit owner acceptance before
rollout (#43).
