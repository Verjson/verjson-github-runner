---
date: 2026-08-24
issue: 166
impact: patch
title: Adopt compact canonical container SBOM attestations
---

Pin the complete generated candidate and release stack to the canonical contract that preserves full SPDX evidence while keeping large Node and Python predicates within GitHub's attestation boundary.

All generated artifacts and reviewed builder identities use immutable Verjson/.github contract `40446f8d34a135bf6e15e9274aa00317d3f20f18`; this follows the blocker and correction recorded in Verjson/.github#1047.
