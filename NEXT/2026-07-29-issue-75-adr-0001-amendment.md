---
date: 2026-07-29
issue: 75
title: Amend ADR-0001 with the current admitted tool matrix
---

ADR-0001 still enumerated the pre-`unzip`/`python3` tool list, so the accepted decision
text trailed the contract `entrypoint.sh` actually enforces. Rather than rewrite a decided
ADR, the document gained an `## Amendments` section recording that the matrix was extended
with `unzip` and `python3` (PRs #60/#74, issue #72) and that the base moved to Ubuntu 26.04
(PR #68), which ships uutils coreutils in place of GNU for the coreutils-provided tools.
The amendment names `attest_ci_runner()` as the normative matrix so the next drift is a
documentation bug rather than an ambiguity. Fixes #75.
