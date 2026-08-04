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

The exact `ci` label, normalized case-insensitively to match GitHub semantics, is a
capability declaration. At container startup, before token minting or runner registration,
the entrypoint must successfully exercise GitHub CLI,
Docker daemon access, Docker Compose, Docker Buildx, Node.js 24, npm, jq, git, bash,
curl, grep, sed, awk, find, base64, tar, and gzip. Admission is mandatory whenever `ci`
is present as a comma-separated label.

The image pins the GitHub CLI and Node.js 24 releases and verifies architecture-specific
upstream SHA-256 checksums during the build. The publish workflow produces
multi-architecture, commit-addressed tags with BuildKit SBOM and provenance attestations
and retains receipts that bind base and kind tags to immutable manifest digests.

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

## Amendments

The decision above is left as it was accepted. Later changes to the admitted tool matrix
are recorded here instead of being edited into the original text.

### 2026-07-29 — admitted matrix extended; base moved to Ubuntu 26.04

- The admitted tool matrix gained `unzip` and `python3`. Actions in common use unpack
  zip artifacts and shell out to Python, so a runner missing either could take a `ci`
  job it could not finish
  ([#60](https://github.com/Verjson/verjson-github-runner/pull/60),
  [#74](https://github.com/Verjson/verjson-github-runner/pull/74),
  issue [#72](https://github.com/Verjson/verjson-github-runner/issues/72)).
- The base image moved to Ubuntu 26.04
  ([#68](https://github.com/Verjson/verjson-github-runner/pull/68)). Ubuntu 26.04 ships
  uutils coreutils in place of GNU coreutils, so the coreutils-provided entries in the
  matrix (`base64` and friends) are now satisfied by uutils implementations. Admission
  checks probe the tool, not its provenance, so a uutils tool that answers `--version`
  admits the runner; behavioural differences between the two implementations are a
  workload concern, not an admission one.

### 2026-08-04 — organization toolchain and PowerShell variant attested

- The base image and normative `ci` admission matrix gained `diff`/`cmp`, PyYAML,
  ShellCheck, and zstd. Admission now also enforces the material runtime floors consumed
  by organization workflows: Node.js >=24.10, Python >=3.10, Bash >=4.3, and jq >=1.6
  ([issue #111](https://github.com/Verjson/verjson-github-runner/issues/111)). Tools that
  workflows provision for themselves, including Helm, actionlint, Pulumi, and Claude,
  remain outside the image contract.
- A multi-architecture PowerShell variant is now published from the same attested base
  with immutable digest receipts, SBOM, and provenance. PowerShell remains a separate
  capability rather than widening `ci`: advertising the exact case-insensitive `pwsh`
  label requires `pwsh --version` before token minting or registration.
- Published variants bind `FROM` to the exact base manifest digest produced by the base
  job rather than its commit-addressed tag. Before every token mint, ephemeral supervisors
  run the candidate image under the planned child's environment, network, and socket
  mounts while retaining child-side `ci` and `pwsh` checks.
- Default labels derive the canonical architecture capability from the runtime (`x64` or
  `ARM64`) in both shell and PowerShell launchers; explicit labels remain
  operator-controlled. Version admission accepts only stable numeric releases, so
  malformed and prerelease output fails closed.

### 2026-08-04 — published digests gain GitHub artifact attestations

- The trusted publication workflow creates a GitHub artifact build provenance
  attestation for the base digest and every kind digest after each multi-architecture
  image is pushed ([issue #113](https://github.com/Verjson/verjson-github-runner/issues/113)).
  It publishes each attestation to GitHub's attestation store and GHCR, using only the
  workflow's short-lived OIDC identity and the repository-scoped `GITHUB_TOKEN`.
- BuildKit's maximal provenance and SBOM attestations remain enabled, and immutable
  digest receipts remain workflow artifacts. These records are complementary: GitHub
  artifact attestations make the publisher identity verifiable by the deployment gate,
  while BuildKit records build details and receipts preserve the release handoff.
- Privileged publication runs only for pushes to `main` and protected `v*` release tags;
  it cannot be dispatched against a caller-selected branch. A main deployment must bind
  verification to the complete workflow identity and protected source ref:
  `gh attestation verify oci://ghcr.io/verjson/gha-runner@<digest> --repo Verjson/verjson-github-runner --signer-workflow Verjson/verjson-github-runner/.github/workflows/publish-images.yml --source-ref refs/heads/main`.
  A release deployment must instead supply the exact tag source ref, for example
  `--source-ref refs/tags/v1.2.3`; a wildcard tag ref is not sufficient.
- The released updater does not yet enforce the signer workflow or source ref. That defect
  is tracked by
  [Verjson/verjson-cli-cloud#225](https://github.com/Verjson/verjson-cli-cloud/issues/225),
  and unattended rollout must remain blocked until the updater is corrected. Verification
  failure remains a fail-closed rollout condition.

`attest_ci_runner()` in `entrypoint.sh` is the normative matrix. Where this document and
that function disagree, the function wins, and the disagreement is a bug in this document.
