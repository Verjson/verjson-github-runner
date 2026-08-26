---
date: 2026-08-26
id: 20260826T000000Z
impact: patch
title: Admit general runners only after Docker bridge routing passes
---

Prevent a host from attaching the `general` label unless its runner container can reach
a disposable sibling on Docker's bridge before credentials are consumed. The immutable,
credential-free admission closes the heterogeneous-pool failure reported in
[`Verjson/.github#1093`](https://github.com/Verjson/.github/issues/1093) and is governed
by ADR 0010.
