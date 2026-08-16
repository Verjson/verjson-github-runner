# 0006 — Classify GHCR retention candidates without deletion authority

- **Date:** 2026-08-16
- **Issue:** [Verjson/verjson-github-runner#146](https://github.com/Verjson/verjson-github-runner/issues/146)
- **Category:** package retention / provenance / deployment safety
- **Status:** Accepted for read-only planning; pruning remains blocked

## Context

`ghcr.io/verjson/gha-runner` accumulates untagged OCI package versions whenever a
multi-architecture image, SBOM, BuildKit provenance record, or GitHub artifact
attestation is published. An untagged version is not necessarily garbage: it can be a
platform manifest referenced by a tagged index, an attestation manifest, a deployment
digest, or a rollback dependency. GitHub's package-version API exposes tags and version
identifiers but does not classify those relationships.

Deleting a published package version is irreversible. Issue #146 asks for policy and
automation but explicitly does not authorize a deletion. A read-only inventory can
establish which versions are related through OCI evidence, but cannot prove that an
untagged digest is absent from every deployment and rollback target.

## Decision

The accepted automation is strictly read-only. It inventories every GitHub package
version, fetches every OCI manifest, validates supported index, image-manifest, artifact,
subject, and descriptor shapes, and fails the entire plan on incomplete, malformed, or
unsupported evidence. All tagged versions are graph roots. Traversal preserves index
children and attached provenance: a tagged subject keeps its referrer manifest and the
index that wraps that referrer. Synthetic `sha256-<digest>` attestation tags are
preserved as tagged versions but do not make an otherwise untagged subject a release
root.

A version is a provisional policy candidate only when it has no tags, is unreachable
from every tagged OCI root, and both its creation and most recent update are at least 30
days old. Using the later timestamp gives a newly untagged old version a fresh grace
period. The plan classifies every untagged version, records the complete inventory
fingerprint and policy candidates, hashes its canonical JSON, explicitly states that
pruning is unauthorized, and is retained as a workflow artifact for audit.

The repository contains no deletion job, package-write permission, apply command,
deletion API call, authorization switch, approval environment, or mutation receipt.
Actual pruning remains blocked until a separate tracked change supplies all of these
governance and evidence prerequisites:

1. explicit authorization to delete published package versions;
2. a pre-existing protected reviewer environment whose governing policy is verified
   fail-closed before use;
3. an operator-supplied identity for a previously reviewed plan, rather than a workflow
   self-approving a plan it just generated;
4. strict durable per-mutation evidence recorded before the request, reconciliation of
   ambiguous outcomes, and a durable outcome checkpoint before another mutation;
5. immediate target revalidation coordinated with publication before every mutation;
6. a fresh, completeness-verifiable deployment-controller receipt covering every
   current deployment and required rollback digest.

## Consequences

- Tagged releases, platform manifests, SBOMs, and provenance reachable from them are
  classified as retained OCI content.
- Unreachable versions are candidates for later review, not approved deletion targets.
- Invalid registry evidence aborts rather than making a version appear unreachable.
- Current deployment and rollback completeness remains unknown until a suitable receipt
  contract exists, so no plan produced by this decision can authorize pruning.
- Billing verification remains a post-deletion operational step after GitHub's 6–12
  hour recalculation window; no such verification is possible without separately
  authorized pruning.

## Rejected alternatives

- **Delete every untagged version after an age threshold** cannot distinguish orphaned
  versions from multi-architecture, provenance, deployment, or rollback dependencies.
- **Keep only the newest N versions** can remove an actively deployed digest or its
  rollback image.
- **Embed a manual deletion job now** exposes irreversible capability before its
  reviewer environment, reviewed-plan identity, deployment receipt, and mutation
  evidence contracts exist.
- **Treat unvalidated JSON as an empty manifest** converts missing evidence into a false
  orphan classification.
