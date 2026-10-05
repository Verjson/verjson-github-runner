---
date: 2026-10-05
issue: 208
title: GitLab isolation acceptance checklist
impact: patch
---

Document the protected GitLab job and admitted-pod evidence required before activating signed candidate and release work. The live namespace probe currently fails to create the Bubblewrap user namespace; issue #208 tracks the runtime correction and remaining acceptance.
