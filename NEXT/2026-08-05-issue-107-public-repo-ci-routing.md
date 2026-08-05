---
date: 2026-08-05
issue: 107
title: Route this public repository's CI to GitHub-hosted runners
---

This repository's `changelog / validate` and `privileged_merge` checks had been queueing
forever with no runner since 2026-08-04, blocking every pull request without failing
anything. The shared persistent lane moved to a runner group that names 89 private
repositories and refuses public ones, while the org routing variables still sent this
public repository's jobs to that lane — a selector that no reachable runner could satisfy.

Repository-level runner variables now pin those jobs to `ubuntu-24.04`, and the generated
privileged-merge caller was regenerated with the canonical generator for the same target
because it hardcodes its labels rather than reading a variable. A new `routing-guard` job
asserts those variables, because the org workflows fall back to a hardcoded
`["self-hosted","general"]` literal that queues rather than failing, so a deleted variable
would otherwise restore the deadlock silently. Admitting a public repository to a group of
persistent shared runners was rejected as the alternative; see
[ADR 0003](docs/decisions/0003-public-repository-ci-routes-to-hosted-runners/README.md).
