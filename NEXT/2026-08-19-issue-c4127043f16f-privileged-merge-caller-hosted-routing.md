---
date: 2026-08-19
id: c4127043f16f
title: Regenerate the privileged-merge caller onto the hosted-routing contract
---

Bump `.github/workflows/ai-privileged-merge.yml`'s pinned contract SHA from
`63fc49c68e46c1915bdc07db29d68f3f76d4377e` to
`c4127043f16fbcfd64f701797ccf0f11c9077317`, the current `Verjson/.github`
main. That range includes PR #796/#809 (Verjson/.github ADR 0089's
2026-08-14 amendment), which routes this repository's privileged merge job
to a disposable GitHub-hosted runner on public, non-fork events instead of
the persistent self-hosted lane — this repository is one of the two names on
the canonical allowlist. Regenerated with
`scripts/gen-privileged-merge-caller.sh`; the only delta is the pinned SHA
(comment and `uses:` line), confirming no drift in the required-checks
shape. Closes the remaining adoption step named in Verjson/.github#676.
