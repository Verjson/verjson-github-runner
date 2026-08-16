# 0007 — Promote immutable container candidates by explicit dispatch

- **Status:** Accepted
- **Date:** 2026-08-16
- **Issue:** [#144](https://github.com/Verjson/verjson-github-runner/issues/144)
- **Supersedes:** The merge-driven stable-publication portion of [ADR 0001](../0001-attested-ci-runner-contract/README.md)
- **Organization decision:** [Verjson/.github ADR 0078](https://github.com/Verjson/.github/tree/4b2554d5b6064e8cd6e4b3ad5edb2a9eb214a6b9/docs/decisions/0078-container-release-and-runner-deployment-contract)
- **Category:** Release authority and production credentials — **sensitive class**

## Context

The attested runner decision required main-branch publication to retain immutable
digests, provenance, SBOMs, and receipts, but its workflow also updated stable aliases
on every merge. A merge therefore exercised release authority without an explicit
versioned promotion and without a retained candidate-to-release handoff.

The organization container contract now separates pull-request validation, immutable
main-branch candidates, stable promotion, and production deployment. Issue #144 adopts
that contract for the complete runner image family.

## Decision

Pull requests build the complete `base`, `rust`, `node`, `python`, `go`, and `pwsh`
matrix without publishing. A push to `main` may publish only immutable commit and
`0.2.0-rc.<run>.<attempt>` candidate identities with the complete multi-architecture
manifest, provenance, SBOM, and same-run base-digest relationship.

Only `.github/workflows/container-release.yml`, invoked by `workflow_dispatch` from the
protected default branch, may promote a retained candidate to the reviewed stable
version. Promotion copies the exact candidate digests to stable aliases and must not
invoke a Dockerfile or rebuild an image. The signed release manifest is authoritative;
mutable aliases are conveniences and are never deployment inputs.

This decision supersedes only ADR 0001's merge-driven stable-publication workflow and
its legacy signer-workflow path. ADR 0001's single shared runner artifact, admission
matrix, exact base-digest layering, multi-architecture requirement, provenance,
BuildKit SBOM, GitHub attestation, immutable receipt, and digest-only deployment
decisions remain in force. The signer identity becomes the pinned canonical candidate
workflow recorded in `container-candidate.json`.

## Consequences

- Merging cannot update stable production aliases.
- Stable release authority is explicit, versioned, auditable, and does not rebuild.
- Every derived image is published in its own repository so one variant cannot replace
  another variant's candidate or stable alias.
- Production rollout consumes the signed release manifest and remains a separate
  operation with its own deployment controls.

## Rejected alternatives

- **Keep stable tags on `main` pushes:** this preserves release-on-merge authority and
  cannot prove an independent promotion decision.
- **Rebuild during release:** a second build would sever the attested candidate-to-release
  digest chain.
- **Share one repository tag across variants:** the canonical candidate identity is a
  version tag, so variants would overwrite one another instead of producing a complete
  immutable set.
