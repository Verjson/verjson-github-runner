---
date: 2026-08-05
issue: 110
title: Refuse registration on hosts without OOM survival headroom
---

Runner admission now proves host memory capacity before a registration credential is
minted, so a host that cannot survive a large dependency install fails loudly at
registration instead of having its job — or its listener — killed mid-run by the kernel.
The budget counts RAM plus swap and must reach `RUNNER_MIN_MEMORY_MB` (default 6144),
which admits the shared lane's 4 GB RAM + 4 GB swap hosts and rejects the swapless 4 GB
configuration that OOM-killed a 1,978-package `npm ci`. Registration also reports any
prior kernel OOM kill explicitly, so the next job log names the kill rather than leaving
a silent listener restart and an absent job log as the only evidence.

Capacity is proven for every runner rather than only those advertising a toolchain
label, because memory exhaustion is not a capability claim.
