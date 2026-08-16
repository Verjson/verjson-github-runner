---
date: 2026-08-16
id: 20260816T190500Z
title: Add held GHCR deletion previews
---

Continue issue #146 by exposing tagged roots, OCI dependencies, and attestations as
explicit protected evidence, then generating a hash-bound dry-run deletion preview
while retaining package-read-only permissions and the irreversible deletion hold
documented by ADR 0009.
