# 0008 — Require an integrity-verified GHCR untagged-observation chain

- **Date:** 2026-08-16
- **Issue:** [Verjson/verjson-github-runner#146](https://github.com/Verjson/verjson-github-runner/issues/146)
- **Category:** package retention / provenance / deployment safety
- **Status:** Accepted for read-only planning; pruning remains blocked
- **Supersedes:** The age-evidence and tag-removal-timing portion of [ADR 0006](../0006-safe-ghcr-retention/README.md)

## Context

ADR 0006 used the later of a package version's `created_at` and `updated_at` values as
the beginning of its untagged grace period. GitHub does not contractually define
`updated_at` as tag-removal time. A version can therefore become untagged without that
timestamp providing trustworthy evidence of when the untagged interval began.

The registry response also needs to prove the identity and byte length of graph nodes.
Parsing plausible JSON alone does not bind the response to the digest requested from
GHCR, and an OCI descriptor edge is incomplete evidence when its declared size differs
from the referenced manifest bytes.

## Decision

The planner starts an untagged version's age floor at the first time a read-only plan
observes that exact package-version ID and digest without tags. It carries that time
forward only from the immediate latest successful main-branch workflow run selected by
the GitHub API. Each plan records its repository, full ref, run ID, run attempt, head
SHA, and deterministic artifact name. Before reuse, the downloaded evidence must match
that exact source plus the API artifact name, ID, size, and SHA-256 digest; the archive
must contain exactly one root `ghcr-retention-plan.json` entry whose canonical plan
hash, schema, policy, identity, timestamps, and observation entries verify. Selecting a
penultimate in-window artifact is therefore a discontinuity, not a valid replay.

The prior plan must be older than the current plan and no more than 14 days old. A
missing, stale, malformed, replayed, future-dated, or otherwise discontinuous plan
resets the floor; a version absent or tagged in the prior inventory also starts a new
floor. Non-main runs never carry prior observations, and prior-evidence preparation
removes its exact output paths before any branch or availability decision so tracked or
stale workspace files cannot become evidence. JSON parsing rejects duplicate keys and
non-finite numbers at every external boundary. Lost evidence reduces candidates to zero
rather than shortening the grace period.

Every fetched raw manifest is hashed byte-for-byte and must match the requested SHA-256
digest before it can contribute evidence. Each graph edge to an inventory manifest must
also declare the exact fetched byte length. These rules cover OCI and Docker indexes,
image manifests, OCI artifact manifests, and subject/referrer relationships. Missing,
malformed, unsupported, hash-mismatched, or size-mismatched evidence aborts the plan.

GitHub API and prior-artifact access run in a credential-scoped workflow step with only
`actions: read`, `contents: read`, and `packages: read`. Registry inspection runs
separately, strips both `GH_TOKEN` and `GITHUB_TOKEN` plus Actions runtime tokens from
every subprocess, and uses a checkout that does not persist credentials.

This decision supersedes only ADR 0006's claim that package timestamps establish a
fresh untagged grace period and strengthens its manifest-integrity requirements. ADR
0006's graph roots, reachability policy, authorization blockers, and strictly read-only
deletion hold remain accepted. No package mutation is authorized. The bounded-retention
and apply design remains blocked by issue #144's canonical package-topology migration.

## Consequences

- The first plan after this change, or after any observation-chain gap, has zero policy
  candidates even when the package contains old unreachable versions.
- Weekly successful main-branch plans can accumulate continuous untagged-age evidence
  without treating mutable package metadata as a tag-removal clock.
- Artifact retention and workflow continuity are safety inputs; losing either delays
  future candidate classification by at least the full age floor.
- Registry mirrors, proxies, and tools that return altered raw bytes or inaccurate OCI
  descriptor sizes fail closed.
- The workflow remains incapable of deletion: it has package-read permission only and
  contains no apply command, authorization switch, protected environment, DELETE call,
  or mutation receipt.

## Rejected alternatives

- **Continue using `updated_at`** relies on API behavior GitHub does not guarantee.
- **Trust an unhashed prior JSON file** permits rollback or tampering to shorten a
  version's observed untagged interval.
- **Carry observations across an unlimited run gap** cannot prove uninterrupted
  visibility of intervening tag changes.
- **Canonicalize a manifest before hashing** proves a transformed JSON value, not the
  exact registry bytes named by the digest.
