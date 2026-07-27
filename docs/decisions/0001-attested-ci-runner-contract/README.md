# 0001: Attested `ci` runner contract

- Status: Accepted
- Date: 2026-07-27
- Issue: [Verjson/verjson-github-runner#29](https://github.com/Verjson/verjson-github-runner/issues/29)

## Context

Verjson and Tequity workflows need the same portable Linux runner capabilities. Mutable
labels and image tags alone do not prove that a runner can execute the required tools,
and registration before validation can make an incomplete runner schedulable. Image
publication also needs an auditable connection between source, package inventory,
provenance, and the deployed manifest.

## Decision

`ghcr.io/verjson/gha-runner` is the single runner-image artifact for both organizations.
No organization-specific image is created.

The exact `ci` label is a capability declaration. At container startup, before token
minting or runner registration, the entrypoint must successfully exercise GitHub CLI,
Docker daemon access, Docker Compose, Docker Buildx, Node.js 24, npm, jq, git, bash,
curl, grep, sed, awk, find, base64, tar, and gzip. Admission is mandatory whenever `ci`
is present as a comma-separated label.

The image pins the GitHub CLI and Node.js 24 releases and verifies architecture-specific
upstream SHA-256 checksums during the build. The publish workflow produces
multi-architecture, immutable commit tags with BuildKit SBOM and provenance attestations
and retains source-to-digest receipts for base and kind images.

Infrastructure rollout is separate. Consumers deploy the recorded digest, preserve
ephemeral/job-clean isolation and existing runner-group allowlists, validate admission,
and retain the previous digest for rollback. PowerShell is not part of this Linux
contract. The later deployment target is two Tequity-accessible DigitalOcean containers;
that rollout remains tracked by
[Verjson/verjson-cli-cloud#88](https://github.com/Verjson/verjson-cli-cloud/issues/88).

## Consequences

- Verjson and Tequity cannot drift onto organization-specific runner images.
- A missing tool or inaccessible Docker daemon prevents `ci` registration before any
  credential is minted.
- Docker socket access remains host-root-equivalent; attestation does not reduce that
  trust boundary.
- Rollout automation must consume immutable digests and record admission evidence.

## Rejected alternatives

- **A Tequity-specific image** would duplicate the artifact and allow capability drift.
- **A caller-controlled admission bypass** would make the `ci` label untrustworthy.
- **Mutable tags without attestations or receipts** would not identify the artifact that
  was validated or provide a durable audit trail.
