# 0004 — Every organization repository may use the shared self-hosted lane

- **Date:** 2026-08-05
- **Issue:** Verjson/verjson-github-runner#107
- **Category:** CI routing / runner-group admission boundary
- **Status:** Accepted — **supersedes [ADR 0003](../0003-public-repository-ci-routes-to-hosted-runners/README.md)**

## Context

ADR 0003 pinned this repository's reusable-workflow jobs to GitHub-hosted
runners. Its reasoning was an admission boundary: runner group 8 `DigitalOcean`
was `visibility: selected` with `allows_public_repositories: false`, this
repository is public, and so its `[self-hosted, general]` jobs queued forever
with no runner and no failing check.

The organization has since adopted a policy that **any Verjson repository,
public or private, must be able to use the self-hosted `general` runners**, and
the group has been reconfigured accordingly:

```json
{ "visibility": "all", "allows_public_repositories": true }
```

Verified in effect: `Verjson/.github` — also public, and previously exhibiting
the same permanent queue — ran `privileged_merge` to completion on
`gha-general-2` immediately after the change.

The condition ADR 0003 worked around no longer exists. Its pins now do the
opposite of what they were for: they *prevent* this repository from using the
lane the policy says it must be able to use.

## Decision

Remove the workaround entirely.

1. Delete the repository-level variables `VERJSON_RUNNER_DEFAULT`,
   `VERJSON_RUNNER_UNTRUSTED`, `VERJSON_RUNNER_ISOLATED`, and
   `VERJSON_RUNNER_FASTLANE`, so this repository inherits organization routing
   like every other consumer.
2. Regenerate `ai-privileged-merge.yml` with the canonical generator at
   `["self-hosted","general"]`, restoring the shared lane.
3. Remove the `routing-guard` job from `test.yml`. It asserted the pins; with
   the pins gone it would fail, and the deadlock it guarded against is now
   prevented at the group rather than per repository.

## Consequences

This repository's CI depends on the runner fleet whose image it builds. ADR 0003
counted losing that dependency as a benefit, and that concern is **not**
invalidated by the policy change — it is simply outranked by it. The risk is
real and worth naming precisely: a defective image published from here can
degrade the lane that this repository's own CI needs in order to publish the
fix.

Two things bound that risk, and neither is new:

- Rollouts are staged one host at a time behind digest attestation and
  fail-closed admission, so a bad image does not reach the whole lane at once.
- The image is validated before publication by `test.yml` and
  `image-build-check.yml`, both of which run on GitHub-hosted runners and are
  therefore unaffected by the state of the fleet.

If the lane is ever fully degraded by an image published here, the recovery path
is the same workaround ADR 0003 documented — repository-level variable pins —
applied deliberately and temporarily rather than standing permanently.

Organization-level routing still governs where jobs actually land.
`VERJSON_RUNNER_OVERFLOW` (Verjson/.github ADR 0053) currently sends polling and
short jobs to hosted capacity for every repository while the lane is
oversubscribed. That is a capacity measure, not an admission constraint: this
repository is now *eligible* for the shared lane, which is what the policy
requires, whether or not a given job is routed there today.

## Note on the tooling

The group reconfiguration conflicts with a documented precondition of
`verjson cloud runner update`, which requires the lane's group to be
`visibility=selected` with public repositories disabled. Fleet image rotation
and host migration are blocked until that is resolved; tracked as
Verjson/verjson-cli-cloud#246. This does not affect the decision above, but it
does mean the fleet cannot currently be updated.
