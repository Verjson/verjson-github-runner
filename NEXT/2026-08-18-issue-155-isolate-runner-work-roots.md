---
date: 2026-08-18
issue: 155
impact: patch
title: Fail closed when a runner work root is already claimed
---

Give every runner process an exclusive, held-for-lifetime lock on its resolved `--work` directory (`claim_work_root`, `entrypoint.sh`) so two runner processes can no longer be admitted onto the same on-disk checkout — the root cause of the `gha-general-10` cross-job workspace corruption on Verjson/.github PR #861. A colliding second process is refused before it touches git state, rather than silently sharing (and corrupting) another job's index/worktree.
