---
date: 2026-08-16
issue: 144
title: Promote immutable runner candidates by explicit dispatch
impact: minor
---

Adopt the canonical Verjson container candidate and release contracts for the complete
multi-architecture runner family. Main pushes now publish only immutable candidates;
stable aliases move only through an exact-digest, no-rebuild release dispatch governed
by ADR 0007. Python bytecode produced by the contract suite is now ignored as test
residue.
