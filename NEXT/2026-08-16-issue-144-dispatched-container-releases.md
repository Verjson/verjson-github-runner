---
date: 2026-08-16
issue: 144
title: Promote immutable runner candidates by explicit dispatch
impact: minor
---

Adopt the canonical Verjson container candidate and release contracts for the complete
multi-architecture runner family. Main pushes now publish only immutable candidates;
stable aliases move only through an exact-digest, no-rebuild release dispatch governed
by ADR 0007. Credential-free standalone checks resolve a verified immutable public base
digest, while canonical publication overrides it with the exact same-run digest. Candidate
and release manifests are attested; serialized stable promotion verifies signed SPDX and
provenance evidence and reconciles the complete alias set before publication. Python
bytecode produced by the contract suite is now ignored as test residue.
