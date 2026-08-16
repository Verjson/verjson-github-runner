# 0006 — Retain every protected GHCR graph and prune only proven orphans

- **Date:** 2026-08-16
- **Issue:** [Verjson/verjson-github-runner#146](https://github.com/Verjson/verjson-github-runner/issues/146)
- **Category:** package retention / provenance / deployment safety
- **Status:** Accepted; deletion remains separately gated

## Context

`ghcr.io/verjson/gha-runner` accumulates untagged OCI package versions whenever a
multi-architecture image, SBOM, BuildKit provenance record, or GitHub artifact
attestation is published. An untagged version is not necessarily garbage: it can be a
platform manifest referenced by a tagged index, an attestation manifest, a deployment
digest, or a rollback dependency. GitHub's package-version API exposes tags and version
identifiers but does not classify those relationships.

Deleting a published package version is irreversible. Issue #146 asks for policy and
automation but explicitly does not authorize a deletion.

## Decision

Retention uses a graph built from the complete GitHub package inventory and every OCI
manifest. All tagged versions are roots. Digests listed in the repository variable
`GHCR_PROTECTED_DIGESTS` are additional roots and must cover current deployments and
the rollback digests retained by the deployment controller. The traversal preserves
index children and attached provenance: a protected subject keeps its referrer
manifest and the index that wraps that referrer. Synthetic `sha256-<digest>`
attestation tags are preserved as tagged versions but do not make an otherwise
unprotected subject a release root.

A version is a candidate only when it has no tags, is at least 30 days old, and is not
reachable from any protected root. Inventory omissions, invalid manifests, missing
deployment digests, registry failures, or more than 5,000 package versions abort the
plan. One application can delete at most 50 of the oldest candidates.

The scheduled workflow is read-only and uploads a hashed JSON plan. Deletion exists
only as a manual `workflow_dispatch` path and remains disabled unless all of these
independent gates hold:

1. mode is `delete` and the dispatcher enters the exact package confirmation;
2. repository variable `GHCR_RETENTION_DELETE_ENABLED` equals
   `ghcr-retention-v1`;
3. the `ghcr-retention-deletion` environment's governing policy grants approval;
4. `GHCR_PROTECTED_DIGESTS` is non-empty and every digest still exists;
5. the plan hash, package inventory, protected digest set, graph decision, and bounded
   delete batch still match immediately before the first API deletion.

Each successful deletion is persisted to a receipt before the next request. This
decision and its workflow do not configure the enablement variable, establish
environment approval rules, or authorize an initial deletion. Those are an explicit
owner action after reviewing a dry-run plan and deployment inventory.

## Consequences

- Tagged releases, current deployments, declared rollback digests, platform manifests,
  SBOMs, and provenance reachable from them survive retention.
- A stale or missing deployment inventory disables deletion instead of guessing.
- Package publication concurrent with approval invalidates the plan and requires a new
  dry run.
- GitHub's deletion API is not transactional. A failure can leave a partially applied
  batch, so receipts are durable evidence and batches are deliberately small.
- Billing verification remains a post-deletion operational step after GitHub's 6–12
  hour recalculation window; no such verification is possible until deletion is
  separately authorized and performed.

## Rejected alternatives

- **Delete every untagged version after an age threshold** cannot distinguish orphaned
  versions from multi-architecture or provenance dependencies.
- **Keep only the newest N versions** can remove an actively deployed digest or its
  rollback image.
- **Automatically delete on a schedule** gives a transient inventory or registry error
  destructive authority without a reviewed plan.
- **Treat attestation tags as release roots** retains their historical subjects forever
  and prevents orphan reclamation; provenance follows protected subjects instead.
