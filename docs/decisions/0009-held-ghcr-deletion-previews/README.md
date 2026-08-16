# 0009 — Materialize GHCR deletion requests only as held previews

- **Date:** 2026-08-16
- **Issue:** [Verjson/verjson-github-runner#146](https://github.com/Verjson/verjson-github-runner/issues/146)
- **Category:** destructive package retention / provenance / deployment safety
- **Status:** Accepted; deletion remains unauthorized
- **Supersedes:** apply-design blocker in [ADR 0008](../0008-integrity-verified-ghcr-observation-chain/README.md)

## Context

The canonical dispatched container lifecycle from issue #144 now defines immutable
candidate and release identities. ADRs 0006 and 0008 deliberately stopped at a
read-only candidate plan because deleting a published package version is irreversible.
Operators still need reviewable evidence showing exactly which version IDs an eventual
apply operation would target and which tagged roots, OCI dependencies, and attestations
the policy protects.

Generating a request and executing it are separate authorities. Combining them would
let a scheduled inventory approve its own evidence and turn an observation race into a
destructive decision.

## Decision

The planner records three explicit protected sets: tagged version identities and tags,
reachable untagged OCI dependencies, and reachable attestation manifests. A separate
`preview` command verifies the plan hash and governing policy, validates every protected
and candidate identity, rejects duplicates or overlap, and emits only a dry-run deletion
manifest. The scheduled and manual workflow uploads that manifest with
`deletion_authorized: false` under package-read permission.

The repository still contains no package-write permission, deletion API call, execution
flag, reviewer environment, or mutation loop. Before any future delete request, an
authorized design must fetch every page again, rebuild and compare the plan immediately
before each mutation, bind current deployments and rollback digests, persist a
pre-request receipt, reconcile ambiguous responses, and persist the outcome before
continuing. That future operation remains a separately held irreversible action.

## Consequences

- Reviewers can inspect an exact, hashed list of held version-ID requests.
- Tagged releases, their literal tags, OCI dependencies, and attestations are explicit
  evidence rather than implicit graph state.
- Concurrent publication or retagging cannot be handled by trusting an old preview; a
  future apply operation must re-inventory and fail closed on any changed evidence.
- Neither scheduled nor manually dispatched workflows can delete a package version.

## Rejected alternatives

- **Add a disabled delete flag:** a boolean is weak authorization and leaves dangerous
  capability reachable with the workflow token.
- **Grant package-write now:** least privilege requires read-only permissions until the
  irreversible operation has separately satisfied its hold.
- **Treat a preview as authorization:** an artifact records evidence; it does not express
  reviewer or deployment-controller consent.
