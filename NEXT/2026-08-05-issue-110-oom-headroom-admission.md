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
configuration that OOM-killed a 1,978-package `npm ci`. A malformed threshold is rejected
rather than tolerated — `08192` would otherwise parse as octal and admit every host —
and `0` disables the check explicitly, saying so in the log.

Registration also reports how many processes the kernel's OOM killer has terminated on
the host since boot, so a vanished job or a silent listener restart has a named cause
instead of only an absent log. The count comes from `/proc/vmstat` rather than `dmesg`,
which the unprivileged runner container cannot read on a host with
`kernel.dmesg_restrict=1`; when the counter itself is unavailable the log says so rather
than letting silence read as "no kills".

Capacity is proven for every runner rather than only those advertising a toolchain
label, because memory exhaustion is not a capability claim.
