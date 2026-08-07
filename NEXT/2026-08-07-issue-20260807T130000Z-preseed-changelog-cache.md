---
date: 2026-08-07
id: 20260807T130000Z
title: Preseed verified changelog tooling
---

Runner images now preload every immutable changelog tooling pin declared in the
image manifest, verify its digest during build and admission, and expose the
root-owned read-only cache through the stable organization contract. This
completes the runner delivery for
[`Verjson/.github#379`](https://github.com/Verjson/.github/issues/379).
