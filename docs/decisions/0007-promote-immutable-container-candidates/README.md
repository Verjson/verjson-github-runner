# 0007 — Promote immutable container candidates by explicit dispatch

- **Status:** Accepted
- **Date:** 2026-08-16
- **Issue:** [#144](https://github.com/Verjson/verjson-github-runner/issues/144)
- **Supersedes:** The merge-driven stable-publication and single-package storage-topology portions of [ADR 0001](../0001-attested-ci-runner-contract/README.md)
- **Organization decision:** [Verjson/.github ADR 0078](https://github.com/Verjson/.github/tree/bced83b95e17c65ed4500c83756e2638f7dbb9d4/docs/decisions/0078-container-release-and-runner-deployment-contract)
- **Category:** Release authority and production credentials — **sensitive class**

## Context

The attested runner decision required main-branch publication to retain immutable
digests, provenance, SBOMs, and receipts, but its workflow also updated stable aliases
on every merge. A merge therefore exercised release authority without an explicit
versioned promotion and without a retained candidate-to-release handoff.

The organization container contract now separates pull-request validation, immutable
main-branch candidates, stable promotion, and production deployment. Issue #144 adopts
that contract for the complete runner image family.

ADR 0001 coupled a shared cross-organization capability contract to storage in one GHCR
package. The canonical candidate identity uses the same candidate version for every
variant, so each variant needs its own package to prevent tag collisions. This changes
only storage topology; the runner family still shares one capability and provenance
contract across organizations.

## Decision

Pull requests build the complete `base`, `rust`, `node`, `python`, `go`, and `pwsh`
matrix without publishing. A push to `main` may publish only immutable commit and
`0.2.0-rc.<run>.<attempt>` candidate identities with the complete multi-architecture
manifest, provenance, SBOM, and same-run base-digest relationship.

Only `.github/workflows/container-release.yml`, invoked by `workflow_dispatch` from the
protected default branch, may promote a retained candidate to the reviewed stable
version. Promotion copies the exact candidate digests to stable aliases and must not
invoke a Dockerfile or rebuild an image. Dispatches for one repository and version are
serialized. Before publication, promotion verifies signed provenance and SPDX evidence,
then reconciles the complete stable-alias set and attests the immutable release manifest.
That signed manifest is authoritative; mutable aliases are conveniences and are never
deployment inputs.

This decision supersedes ADR 0001's merge-driven stable-publication workflow, legacy
signer-workflow path, and requirement that every variant share one GHCR package. ADR
0001's shared capability contract, admission matrix, exact base-digest layering,
multi-architecture requirement, provenance, BuildKit SBOM, GitHub attestation,
immutable receipts, and digest-only deployment decisions remain in force. The signer
identity becomes the pinned canonical candidate workflow recorded in
`container-candidate.json`.

## Consequences

- Merging cannot update stable production aliases.
- Stable release authority is explicit, versioned, auditable, and does not rebuild.
- Concurrent promotion cannot race the same stable version, and publication stops unless
  the complete alias set resolves to the selected candidate digests.
- Production consumers can require signed provenance, SPDX evidence, and an attested
  release manifest rather than trusting registry aliases.
- Every derived image is published in its own repository so one variant cannot replace
  another variant's candidate or stable alias.
- The runner family remains one shared cross-organization capability and provenance
  contract even though variants use separate GHCR packages.
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
