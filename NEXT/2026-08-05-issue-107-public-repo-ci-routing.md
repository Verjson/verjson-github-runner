---
date: 2026-08-05
issue: 107
title: Route this public repository's CI to GitHub-hosted runners
summary: This public repository's CI now runs on GitHub-hosted `ubuntu-24.04` runners. Its `changelog / validate` and `privileged_merge` checks had been queueing indefinitely with no eligible runner, because org-level routing still sent them to a shared self-hosted lane whose runner group names 89 private repositories and refuses public ones - a selector nothing could satisfy, which blocked every pull request without failing anything. Repository-level runner variables now pin the target, the generated privileged-merge caller hardcodes it, and a `routing-guard` job asserts the variables so the org-level fallback cannot silently strand checks again.
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
