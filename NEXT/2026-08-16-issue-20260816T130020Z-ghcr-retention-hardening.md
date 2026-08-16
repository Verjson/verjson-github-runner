---
date: 2026-08-16
id: 20260816T130020Z
refs: 146
impact: patch
title: Harden read-only GHCR retention evidence for issue 146
---

Replace package timestamp assumptions with a hash-chained first-observed-untagged
floor that resets fail-closed when prior evidence is unavailable or discontinuous.
Bind raw OCI manifests to requested digests and descriptor sizes, isolate GitHub
credentials from registry inspection, and bind prior observations to the exact latest
successful main-branch run and API-verified artifact archive so stale-workspace and
penultimate-run replays reset rather than continue the chain. Preserve issue #146's
existing zero-candidate and strictly read-only deletion hold.
