# 0003 — Route this public repository's CI to GitHub-hosted runners

- **Date:** 2026-08-05
- **Issue:** Verjson/verjson-github-runner#107
- **Category:** CI routing / runner-group admission boundary
- **Status:** Accepted

## Context

This repository's own CI silently stopped running two required checks. Between
2026-08-04T03:21Z (last success) and 2026-08-04T12:25Z, every `changelog /
validate` and `privileged_merge` job entered `queued` with no runner and stayed
there. No check failed, no error was raised, and no run was cancelled — the jobs
simply never received a runner, so pull requests sat `BLOCKED` on checks that
could never resolve.

The cause is an admission boundary, not capacity. On 2026-08-04 the shared
persistent lane moved from the retired `GCP` runner group to group 8
`DigitalOcean`, whose allowlist names 89 **private** repositories and sets
`allows_public_repositories: false`. This repository is **public**. It was
therefore not in the allowlist, and could not have been: the group refuses
public repositories by configuration.

Meanwhile the org routing variables send work here anyway. The canonical
`changelog-validate.yml` resolves its runner as:

```
inputs.runner       — if the caller passed one, else
'ubuntu-24.04'      — if the owner is not Verjson, else
vars.VERJSON_RUNNER_DEFAULT     — if the repository is private, else
vars.VERJSON_RUNNER_UNTRUSTED || vars.VERJSON_RUNNER_DEFAULT
```

For a public Verjson repository the last branch applies, and the org sets
`VERJSON_RUNNER_UNTRUSTED = ["self-hosted","general"]` — the shared persistent
lane. So a public repository is routed to a group that denies public
repositories. The result is a permanent queue: the exact silent-deadlock
signature of Verjson/.github#182, and the failure mode #115 exists to detect.

`ai-privileged-merge.yml` reaches the same place by a different route. It is a
generated caller that **hardcodes** `runner_labels: '["self-hosted","general"]'`
rather than reading a variable, so no variable change can redirect it.

## Decision

Route this repository's reusable-workflow jobs to GitHub-hosted runners.

1. Set repository-level variables, which override the org values for this
   repository only:

   ```
   VERJSON_RUNNER_DEFAULT   = ["ubuntu-24.04"]
   VERJSON_RUNNER_UNTRUSTED = ["ubuntu-24.04"]
   VERJSON_LANE_UNTRUSTED   = ["ubuntu-24.04"]
   VERJSON_LANE_FALLBACK    = ["ubuntu-24.04"]
   ```

2. Regenerate `ai-privileged-merge.yml` with the canonical generator at
   `Verjson/.github` — `gen-privileged-merge-caller.sh '["ubuntu-24.04"]'` —
   rather than hand-editing the label, because the job key, `uses:` target, and
   `with:` values fail silently when wrong.

The alternative — admitting this repository to group 8 and enabling public
repositories on it — is **rejected**. That group carries persistent, shared,
non-ephemeral runners. Enabling public repositories would expose them to fork
pull requests, which is precisely what the `isolated` lane
(`ephemeral`, `untrusted-pr`, `no-host-docker`) exists to contain. Restoring one
repository's checks is not worth converting a shared persistent lane into a
target reachable by untrusted contributors.

## Consequences

This repository's CI no longer depends on the runner fleet whose image it
builds. That dependency was circular: a defective image published from here
could disable the CI needed to publish the fix. Losing it is a benefit, not a
cost.

The repository's workflows were already partly GitHub-hosted — `test.yml`,
`image-build-check.yml`, and `publish-images.yml` all pin `ubuntu-latest` or
`ubuntu-24.04` directly. This change makes the remaining reusable-workflow jobs
agree with that existing choice instead of inheriting an org default written for
private consumers.

Publishing still produces images for the self-hosted fleet; only the CI that
validates them moves. Image provenance is unaffected, since attestations bind
the `publish-images.yml` signer identity rather than the runner that produced
them.

One consequence is deliberately accepted: the privileged merge for this
repository now executes on a GitHub-hosted runner. The trust logic is unchanged
— it lives entirely in `Verjson/.github@main`, which the caller pins as its
trust anchor, and the caller still grants exactly one secret rather than its
whole store.

## Follow-up

The org-level default is the more general defect and is not fixed here: pointing
`VERJSON_RUNNER_UNTRUSTED` at the shared persistent lane routes *untrusted* work
onto persistent shared hosts for every public Verjson repository. Today that
fails closed by accident, because the runner group denies public repositories.
Should anyone ever enable public repositories on that group to "fix" the queue,
it would fail open instead. Reported to `Verjson/.github` for an org-level
correction.
