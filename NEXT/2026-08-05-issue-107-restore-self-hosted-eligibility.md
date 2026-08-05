---
date: 2026-08-05
issue: 107
title: Restore this repository's eligibility for the shared self-hosted lane
---

The organization now requires every repository, public or private, to be able to use the
self-hosted `general` runners, and runner group 8 was reconfigured to `visibility: all`
with public repositories allowed. The admission boundary that ADR 0003 worked around no
longer exists, so its repository-level routing pins have been removed, the privileged-merge
caller regenerated at `["self-hosted","general"]`, and the `routing-guard` job — which
asserted those pins — dropped.

[ADR 0004](docs/decisions/0004-every-repository-may-use-the-shared-lane/README.md)
supersedes ADR 0003 and records the dependency this reintroduces: this repository's CI now
relies on the fleet whose image it builds. Fleet updates are separately blocked by a
tooling precondition that conflicts with the new group configuration
(Verjson/verjson-cli-cloud#246).
