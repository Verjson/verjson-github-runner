---
date: 2026-08-25
issue: 170
impact: patch
title: Restore App-backed terminal workflow startup
---

Regenerate both terminal-promotion callers at immutable Verjson/.github contract
`6462e0cc72f4d96baa4f8ff8a862db4af0f93db7`, granting exactly the non-writing reads
required to instantiate the reusable workflow while retaining App-only merge authority.
