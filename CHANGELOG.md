# v0.2.1

## Adopt bounded GHCR readiness

Pin the canonical container-candidate workflows, validator, and contract test to
Verjson/.github#1152 so publication waits for exact digest visibility before
requesting provenance attestations.

_Date: 2026-08-27; issue #192_

## Prepare v0.2.1 hosted-provenance runner release

Advance the reviewed stable container version to v0.2.1 so the hosted-provenance
candidate can be promoted without changing the immutable v0.2.0 release.

_Date: 2026-08-27; issue #190_

## Adopt independently hosted runner provenance

Adopt the canonical container publication and release contract that keeps the
managed runner fleet outside its own deployment provenance root.

_Date: 2026-08-27; issue #188_

## Align standalone images with the retained base release

Pin standalone derived-image validation and the PowerShell image to the base
index retained by the immutable v0.2.0 release manifest.

_Date: 2026-08-27; issue #186_

## Adopt bounded 30-minute OCI retention

Regenerate immutable candidate and release surfaces at the canonical contract with a retention-only 30-minute execution ceiling.

_Date: 2026-08-27; issue #184_

## Adopt retained OCI artifact graph traversal

Regenerate immutable candidate and release surfaces at the canonical contract that preserves artifact nodes while validating and traversing all declared retained children.

_Date: 2026-08-27; issue #182_

## Adopt artifact-preserving OCI retention

Regenerate the immutable candidate and release surfaces at the canonical contract that preserves OCI artifacts and digest-binds untagged retention inspection.

_Date: 2026-08-27; issue #180_

## Adopt lowercase GHCR retention namespaces

Regenerate the immutable container-release contract at the canonical lowercase GHCR retention fix so post-promotion image retention inspects valid OCI references.

_Date: 2026-08-27; issue #178_

# v0.2.0

## Adopt the repaired container release preflight

Regenerate immutable candidate and release artifacts from the canonical contract that
binds both candidate identity captures and requires Python 3 for release validators.

_Date: 2026-08-27; id:20260827T035300Z_

## Adopt the Python 3 container release contract

Regenerate immutable container candidate and release artifacts from the canonical
Python 3 release contract.

_Date: 2026-08-27; id:20260827T031000Z_

## Adopt the repaired container candidate contract

Regenerate the candidate workflow, manifest validator, and contract test from
the immutable Verjson/.github container-candidate contract. Bind every image,
including the PowerShell runner variant, to the reviewed publisher identity.

_Date: 2026-08-27; id:20260827T000000Z_

## Admit general runners only after Docker bridge routing passes

Prevent a host from attaching the `general` label unless its runner container can reach
a disposable sibling on Docker's bridge before credentials are consumed. The immutable,
credential-free admission closes the heterogeneous-pool failure reported in
[`Verjson/.github#1093`](https://github.com/Verjson/.github/issues/1093) and is governed
by ADR 0010.

_Date: 2026-08-26; id:20260826T000000Z_

## Exercise the App-backed terminal merge caller

Track the controlled exact-head canary for the regenerated App-backed terminal merge
caller, including normal CI, independent review, repository-scoped token mint, and the
App-authored squash-merge receipt.

_Date: 2026-08-25; issue #172_

## Restore App-backed terminal workflow startup

Regenerate both terminal-promotion callers at immutable Verjson/.github contract
`6462e0cc72f4d96baa4f8ff8a862db4af0f93db7`, granting exactly the non-writing reads
required to instantiate the reusable workflow while retaining App-only merge authority,
and bind terminal authorization to the active `changelog / validate` check identity.

_Date: 2026-08-25; issue #170_

## Adopt fail-closed container candidate retry idempotency

Pin the complete generated candidate and release stack, including every reviewed
builder identity and the retry verifier digest, to immutable Verjson/.github contract
`8e41acc640282234bfb82559d31463037e001a60`.

_Date: 2026-08-25; issue #168_

## Adopt compact canonical container SBOM attestations

Pin the complete generated candidate and release stack to the canonical contract that preserves full SPDX evidence while keeping large Node and Python predicates within GitHub's attestation boundary.

_Date: 2026-08-24; issue #166_

## Refresh the standalone derived-image base digest

Pin standalone derived-image validation to the current retained multi-platform base
manifest after the previous untagged package version was removed from GHCR.

_Date: 2026-08-24; issue #165_

## Adopt organization-neutral canonical CI credentials

Pinned generated CI contracts now consume neutral lane variables and mint the
repository-bound Contents-only Release App token for terminal Git/GitHub Release
writes, while job-scoped package authority handles GHCR promotion and retention.

_Date: 2026-08-24; issue #163_

## Bind terminal merge to the dedicated App

Regenerate both terminal-promotion callers at organization contract `c4250f4dae20315ce3472525115c8f0904385f88`. They now pass only the merge App client ID and private key, eliminating terminal merge access to the organization PAT.

_Date: 2026-08-23; issue #991_

## Regenerate the privileged-merge caller onto the hosted-routing contract

Regenerate both `.github/workflows/ai-privileged-merge.yml` and
`.github/workflows/ai-promotion-retry.yml` at the immutable
`f185ba0fcb1045b9dbe8c79e879c19a5b789ee4d` `Verjson/.github` contract. The
contract preserves this public repository's allowlisted disposable
GitHub-hosted route while synchronizing both terminal-merge entry points on
ADR 0118's admitted hosted-lane policy. The generated callers retain the
reviewed required-check identities and promotion-retry workflow set without a
repository-specific `runner_labels` override. Closes the remaining adoption
step named in Verjson/.github#676.

_Date: 2026-08-19; id:c4127043f16f_

## Fail closed when a runner work root is already claimed

Give every runner process an exclusive, held-for-lifetime lock on its resolved `--work` directory (`claim_work_root`, `entrypoint.sh`) so two runner processes can no longer be admitted onto the same on-disk checkout — the root cause of the `gha-general-10` cross-job workspace corruption on Verjson/.github PR #861. A colliding second process is refused before it touches git state, rather than silently sharing (and corrupting) another job's index/worktree.

_Date: 2026-08-18; issue #155_

## Inherit the organization Renovate policy

Remove the repository-local Renovate configuration override so dependency updates inherit the authoritative organization policy without a copied policy surface that can drift.

_Date: 2026-08-16; issue #151_

## Publish the canonical generated-artifacts check

Regenerate the changelog caller, renderer, and contract test from Verjson/.github at the immutable organization-contract pin so pull requests publish `generated-artifacts / validate` instead of the retired changelog context.

_Date: 2026-08-16; issue #149_

## Add read-only GHCR retention planning

Define the destructive package-retention boundary in ADR 0006 and add a strictly
read-only, auditable inventory plan for `ghcr.io/verjson/gha-runner`. The planner
validates OCI evidence, preserves newly untagged versions through a fresh age floor, and
identifies provisional policy candidates; pruning remains blocked on separate explicit
authorization and complete deployment, review, and per-mutation evidence contracts.

_Date: 2026-08-16; issue #146_

## Promote immutable runner candidates by explicit dispatch

Adopt the canonical Verjson container candidate and release contracts for the complete
multi-architecture runner family. Main pushes now publish only immutable candidates;
stable aliases move only through an exact-digest, no-rebuild release dispatch governed
by ADR 0007. Credential-free standalone checks resolve a verified immutable public base
digest, while canonical publication overrides it with the exact same-run digest. Candidate
and release manifests are attested; serialized stable promotion verifies signed SPDX and
provenance evidence and reconciles the complete alias set before publication. Python
bytecode produced by the contract suite is now ignored as test residue.

_Date: 2026-08-16; issue #144_

## Add held GHCR deletion previews

Continue issue #146 by exposing tagged roots, OCI dependencies, and attestations as
explicit protected evidence, then generating a hash-bound dry-run deletion preview
while retaining package-read-only permissions and the irreversible deletion hold
documented by ADR 0009.

_Date: 2026-08-16; id:20260816T190500Z_

## Harden read-only GHCR retention evidence for issue 146

Replace package timestamp assumptions with a hash-chained first-observed-untagged
floor that resets fail-closed when prior evidence is unavailable or discontinuous.
Bind raw OCI manifests to requested digests and descriptor sizes, isolate GitHub and
Actions/OIDC credential variables from registry inspection, and bind prior observations
to the exact latest successful main-branch run and API-verified artifact archive so
stale-workspace and penultimate-run replays reset rather than continue the chain. Preserve issue #146's
existing zero-candidate and strictly read-only deletion hold.

_Date: 2026-08-16; id:20260816T130020Z; refs #146_

## Update build provenance attestations to v4.2.2

- Update both image publication jobs to the immutable `actions/attest-build-provenance` v4.2.2 revision while preserving their digest and registry-attestation contract.

_Date: 2026-08-16; id:20260816T015906Z_

## Restore the organization vulnerability policy to the local Renovate copy

- Resync `renovate.json` with `Verjson/renovate-config` `default.json`. The local copy had drifted to 4 of 10 package rules and was missing `vulnerabilityAlerts` entirely, so the organization's vulnerability remediation policy did not apply to this repository at all.
- Restore the peer-range and Node engine floors, the TypeScript 7 hold, the workflow Node contract-input guard, the generated changelog/release pin guard, and per-Action update grouping.
- Record why the copy exists and what it deliberately omits, so it is resynced rather than re-derived — it is removed once Verjson/renovate-config#7 gives public adopters a central distribution path.

_Date: 2026-08-16; id:20260816T003739Z_

## Restore the canonical AI review gate callers

Regenerate the complete AI review authorization, review, privileged-merge, and promotion-retry caller set from the immutable organization contract so pull requests can obtain a trustworthy review authorization signal again. Issue #143 records the same consumer-drift failure.

_Date: 2026-08-15; issue #139_

## Ship a native addon build toolchain in the base image

- Install `build-essential` and `pkg-config` in the base image so an npm install script that falls back from a prebuilt binary to `node-gyp rebuild` builds from source instead of failing the job.
- Extend the `ci` admission contract to prove the C compiler, a C++ compiler, `make`, and `pkg-config`, so a runner that lost the toolchain refuses to start rather than failing a job halfway through.
- Leave CMake out deliberately: no current consumer needs a `cmake-js` source build, cmake-js provisions its own CMake when one is, and the package measured a further 96 MB on top of the toolchain's 411 MB.

_Date: 2026-08-15; issue #136_

## Ignore Serena agent tooling residue

- Add `.serena/` to the agent tooling residue block in `.gitignore`, alongside `.tokensave/`, so an assistant's index directory cannot be committed and stops reporting the checkout as dirty.

_Date: 2026-08-15; id:20260815T140000Z_

## Retry terminal AI promotion after runner CI completes

Add the generated AI terminal-promotion retry bridge pinned to organization contract `be4da6b739d36b1264f43b8509b995b2edaecad9` for `changelog`, `image build check`, and `test` pull-request workflows.

_Date: 2026-08-09; id:20260809T210004Z_

## Allow on-demand warm-cache image checks

- Add an explicit `amd64` workflow-dispatch mode so cache retention can be measured without manufacturing a pull request.
- Preserve the cold arm64 verification as the default on-demand build.

_Date: 2026-08-08; issue #129_

## Correct the hosted-runner routing fragment identity

Correct the hosted-runner CI routing changelog entry to use its introducing commit identity instead of linking unrelated issue #107.

_Date: 2026-08-07; issue #124_

## Stop pull requests duplicating the image cache

Pull request image checks now read the default branch's BuildKit cache without exporting duplicate branch-scoped copies, preserving cache headroom for the published base and kind images.

_Date: 2026-08-07; issue #122_

## Preseed verified changelog tooling

Runner images now preload every immutable changelog tooling pin declared in the
image manifest, verify its digest during build and admission, and expose the
root-owned read-only cache through the stable organization contract. This
completes the runner delivery for
[`Verjson/.github#379`](https://github.com/Verjson/.github/issues/379).

_Date: 2026-08-07; id:20260807T130000Z_

## chore(changelog): move the contract pin to f12dca7

The changelog contract pin moves from `1486d44d` to `f12dca7`, and the three canonical
adopter artifacts — `.github/workflows/changelog.yml`, `scripts/render-next.sh` and
`scripts/changelog-contract.test.sh` — are regenerated from
`Verjson/.github/scripts/gen-changelog-caller.sh` at that commit. Seven `NEXT/` fragments
gain a `summary:` line, because at this pin a released snapshot carries the release note
rather than the whole diary entry, and those seven led with the problem they solved instead
of what they shipped.

_Date: 2026-08-05; issue #123_

## Cache and parallelise the pull request image build check

The pull request image build check now builds through a new `docker-bake.hcl`, fanning the base image, the four kind images and the pwsh variant out of a single concurrent bake solve and reading the `type=gha` cache that `publish-images.yml` already populates on `main`. Each image reads and writes its own cache scope, so the builds no longer overwrite one another's cache index, and thin variants export `mode=min` so re-exporting unchanged base layers cannot push the repository past its Actions cache quota. The weekly emulated arm64 leg deliberately builds cold, because a cache hit would skip the checksum verification it exists to exercise. What the check proves is unchanged - still amd64-only, build-only, pushing nothing and holding no registry credential.

_Date: 2026-08-05; issue #119_

## Refuse registration on hosts without OOM survival headroom

Runner admission now proves host memory capacity before a registration credential is
minted, so a host that cannot survive a large dependency install fails loudly at
registration instead of having its job — or its listener — killed mid-run by the kernel.
The budget counts RAM plus swap and must reach `RUNNER_MIN_MEMORY_MB` (default 6144),
which admits the shared lane's 4 GB RAM + 4 GB swap hosts and rejects the swapless 4 GB
configuration that OOM-killed a 1,978-package `npm ci`. A malformed threshold is rejected
rather than tolerated — `08192` would otherwise parse as octal and admit every host —
and `0` disables the check explicitly, saying so in the log.

_Date: 2026-08-05; issue #110_

## Restore this repository's eligibility for the shared self-hosted lane

The organization now requires every repository, public or private, to be able to use the
self-hosted `general` runners, and runner group 8 was reconfigured to `visibility: all`
with public repositories allowed. The admission boundary that ADR 0003 worked around no
longer exists, so its repository-level routing pins have been removed, the privileged-merge
caller regenerated at `["self-hosted","general"]`, and the `routing-guard` job — which
asserted those pins — dropped.

_Date: 2026-08-05; id:881157e_

## Route this public repository's CI to GitHub-hosted runners

This public repository's CI now runs on GitHub-hosted `ubuntu-24.04` runners. Its `changelog / validate` and `privileged_merge` checks had been queueing indefinitely with no eligible runner, because org-level routing still sent them to a shared self-hosted lane whose runner group names 89 private repositories and refuses public ones - a selector nothing could satisfy, which blocked every pull request without failing anything. Repository-level runner variables now pin the target, the generated privileged-merge caller hardcodes it, and a `routing-guard` job asserts the variables so the org-level fallback cannot silently strand checks again.

_Date: 2026-08-05; id:5a98108_

## Publish GitHub-verifiable image provenance

The trusted image publication workflow now creates GitHub artifact build provenance
attestations for every published base and kind digest without removing BuildKit SBOM,
provenance, or immutable digest receipts. A wired workflow contract locks the minimal
attestation permissions, main-only trigger, immutable official-action pins, and required
publication steps. Deployment verification must bind the full signer workflow identity
and `refs/heads/main`; the released updater does not yet do so, as tracked by
Verjson/verjson-cli-cloud#225.

_Date: 2026-08-04; issue #113_

## Complete the attested CI toolchain image

The published base now installs and admits the complete fixed organization CI toolchain,
including material runtime floors. A separately labeled multi-architecture PowerShell
variant layers on the exact base manifest digest and receives immutable digest receipts,
SBOM, and provenance. Shell and PowerShell launchers advertise accurate runtime
architecture labels, and supervisors fail closed by running a credential-free,
child-equivalent `ci`/`pwsh` candidate before minting registration credentials.

_Date: 2026-08-04; issue #111_

## Install canonical privileged merge caller

Install the generated thin caller for the organization trusted merge workflow so green adversarial reviews can complete matched-head squash merges without waiting for a second human reviewer. The caller exposes only `ORG_ADMIN_TOKEN` and inherits the provenance, CI, hold, and head-SHA checks defined by Verjson/.github ADRs 0036, 0042, 0043, and 0044.

_Date: 2026-08-02; issue #105_

## Regenerate the changelog contract test so it survives a release

`scripts/changelog-contract.test.sh` is now generated by
`gen-changelog-caller.sh contract-test` instead of hand-written. The previous
copy greped fragment titles by name and asserted a pre-release view of released
history, both of which a release makes false. This repository has no
`release.yml` yet, so the failure was latent rather than active — adding one
would have re-armed it.

_Date: 2026-08-02; issue #103_

## Adopt the canonical changelog contract

This repository now uses the canonical Verjson changelog contract instead of the local fork of the tooling it had been running since #81. `scripts/render-next.sh` and `.github/workflows/changelog.yml` are generated from `Verjson/.github` at one pinned contract commit and delegate to that contract rather than reimplementing it, so the renderer and the validator can no longer drift apart silently. Every fragment moves to `NEXT/YYYY-MM-DD-issue-<identity>-<slug>.md` carrying `date`, `issue` or `id`, and `title` metadata that matches its filename, and the root `NEXT.md` pointer is deleted so `NEXT/` is the sole unreleased store.

_Date: 2026-08-01; issue #101_

## Correct the README's account of the root Dockerfile

The README called the root `Dockerfile` a pre-`images/` leftover kept only for backward
compat, which invited operators to dismiss the file their own hosts run: `setup.sh` and
`docker-compose.yml` both build it, and `Dockerfile.pwsh` now layers on it. The note now
describes the actual split — root `Dockerfile` for the persistent compose/`setup.sh` lane,
`images/base.Dockerfile` for the portable published image carrying the `ci` contract.
Fixes #93.

_Date: 2026-07-29; issue #93_

## Build the pwsh variant in the PR image check

`.github/workflows/image-build-check.yml` now builds `Dockerfile.pwsh` on the root image
built earlier in the same job, and `Dockerfile.pwsh` joins the workflow's `paths:` filter.
The variant landed in #91 without this wiring only because that PR would have collided
textually with #89, which rewrote the workflow.

_Date: 2026-07-29; issue #92_

## Key the image build check concurrency group on the event

`.github/workflows/image-build-check.yml` grouped its concurrent runs by `github.ref`
only. Pull requests each have their own ref, but `schedule` and `workflow_dispatch` both
report `refs/heads/main`, so an on-demand arm64 build and the weekly cron shared one group
and `cancel-in-progress` let either kill the other — exactly when someone triggers a manual
run because they want an arm64 answer now. The group now includes `github.event_name`, so
each trigger cancels only its own kind. Fixes #90.

_Date: 2026-07-29; issue #90_

## PowerShell runner variant, as a separate tag

A new `Dockerfile.pwsh` layers PowerShell 7.6.4 onto the persistent-lane root image and ships as its own tag, so lanes that need `pwsh` get a runner able to execute PowerShell suites while the image everyone else builds stays lean. The version is pinned and checksum-verified per architecture against Microsoft's published hashes rather than installed from the apt repository, where it would float with build date. It deliberately stays outside `images/`, which builds the portable `ci` contract image that PowerShell is excluded from by agreement.

_Date: 2026-07-29; issue #88_

## Catch arm64 image breakage on a schedule, not on main

The image build check now also runs on a weekly schedule and on demand, adding a `base-arm64` job that sets up QEMU and builds `images/base.Dockerfile` for `linux/arm64`, build-only. The per-arch `GH_SHA256_ARM64` and `NODE_SHA256_ARM64` pins had never been exercised before merge, so an upstream re-release or an arm64-only package gap first surfaced when `publish-images.yml` built the real multi-arch image on `main`. Emulated arm64 is far too slow to gate every pull request, so it is proven periodically instead, and the amd64 jobs are gated to `pull_request` so the cron runs only the arm64 leg.

_Date: 2026-07-29; issue #87_

## Ignore agent-tooling residue

Agent-tooling residue - `.claude/worktrees/`, `.tokensave/`, local settings, headroom markers, and an uninvited project-level `AGENTS.md` - is now gitignored, so it can never be committed and never dirties `git status`, matching the convention adopted in `Verjson/.github`.

_Date: 2026-07-29; issue #82_

## Build the runner images on pull requests

New workflow `.github/workflows/image-build-check.yml` builds `images/base.Dockerfile`,
the four kind images, and the root `Dockerfile` on `pull_request`, amd64 only and
build-only (nothing pushed, no registry credential). Until now neither Dockerfile was
built before merge: `publish-images.yml` triggers on push to `main` and tags, and
`test.yml` runs only the shell and Go suites, so a broken image change — bad base
codename, renamed apt package, checksum drift — first surfaced as a published `:latest`
that hosts pull.

_Date: 2026-07-29; issue #79_

## Stamp the isolation-supervisor contract label on the base image

`images/base.Dockerfile` now sets the OCI config label
`com.verjson.gha-runner.isolation-supervisor="1"`, and every kind image inherits it via
`FROM ${BASE_IMAGE}`. Isolated-mode admission in `@verjson/cli-cloud`
(`runner-image-contract`) previously had to fall back to a hard-coded digest allowlist,
which meant each new image publish needed a CLI release before it could be deployed in
isolated mode; the label lets images self-describe the contract instead. The value
versions the supervisor admission contract and consumers fail closed on values they do
not recognize, so bump it only on an incompatible change. SECURITY.md's Image
Supply-Chain Integrity section documents the label. Fixes #78.

_Date: 2026-07-29; issue #78_

## Migrate the running log to per-entry fragments

Split the prepend-only `NEXT.md` into one file per entry under `NEXT/`, rendered
newest-first by `scripts/render-next.sh`, matching the org reference shape in
`Verjson/.github`. A shared, prepend-only log makes every concurrent PR collide
on the same first lines: PR #74 needed a rebase round purely for that, and a
conflicted PR is worse than noisy — GitHub runs no `pull_request` workflows at
all on a conflicting head, so PR #76 sat with zero CI signal until the log was
untangled. A file per entry can never conflict. Refs #77.

_Date: 2026-07-29; issue #77_

## Amend ADR-0001 with the current admitted tool matrix

ADR-0001 still enumerated the pre-`unzip`/`python3` tool list, so the accepted decision
text trailed the contract `entrypoint.sh` actually enforces. Rather than rewrite a decided
ADR, the document gained an `## Amendments` section recording that the matrix was extended
with `unzip` and `python3` (PRs #60/#74, issue #72) and that the base moved to Ubuntu 26.04
(PR #68), which ships uutils coreutils in place of GNU for the coreutils-provided tools.
The amendment names `attest_ci_runner()` as the normative matrix so the next drift is a
documentation bug rather than an ambiguity. Fixes #75.

_Date: 2026-07-29; issue #75_

## Verify supervisor cleanup after expected SIGTERM

Keep the SIGTERM integration check running through expected supervisor
termination so it can verify child-container cleanup, while rejecting
unexpected supervisor exit statuses (#56).

_Date: 2026-07-29; issue #56_

## Report dashboard restart failures

Report dashboard restart failures with actionable relaunch-via-setup guidance
while preserving the runner refresh after a successful restart (#54).

_Date: 2026-07-29; issue #54_

## Report PAT FIFO reader timeouts

Report a typed, actionable timeout when PAT delivery cannot open its FIFO
because no reader connects before the deadline, while preserving the
underlying system error for diagnosis (#53).

_Date: 2026-07-29; issue #53_

## Document `general` as the provider-neutral lane label

The runner docs described kind labels (`rust`, `node`, …) and the `ci` contract, but never
the lane axis, so the shared persistent pool was reachable only through provider-named
labels (`GCP`, `gce`). That made a cloud move a code change: every consumer's `runs-on`
would have had to be rewritten, or DigitalOcean runners mislabelled `GCP`. The README now
documents `general` and `isolated` as the two lanes, states that provider and host names
are never lane labels, and repeats that `isolated`'s companion labels (`untrusted-pr`,
`ephemeral`, `no-host-docker`) are enforced security properties rather than description.
`SECURITY.md` drops the provider name from the runner-group reference for the same reason.

_Date: 2026-07-29; id:d333a3f_

## Migrate the Charm TUI stack to v2

Migrate the Charm TUI stack (bubbletea, huh, lipgloss) to v2 in one change,
since the three majors share the `charmbracelet/x/*` support modules and
cannot land separately. The canonical v2 import paths are now
`charm.land/*/v2`. Styled output printed outside Bubble Tea now goes through
the lipgloss printers so ANSI is still stripped when stdout is not a TTY
(#69, #70, #71).

_Date: 2026-07-29; id:92a3f44_

## Correct what the lane-label docs claim this image enforces

The lane-label documentation now states the isolated-runner enforcement boundary explicitly rather than overstating it in three ways that would each have misled an operator provisioning an isolated runner. It names `untrusted-pr` as the trigger for the contract check rather than one of three interchangeable required labels, scopes the check to supervisor mode instead of claiming it runs at admission, and drops the claim that every runner carries exactly one lane. `SECURITY.md` also loses the provider name from its isolated-admission heading, and `verjson cloud runner <lane>` is disambiguated from the provider host bullets beneath it.

_Date: 2026-07-29; id:79e18e9_

## Ship `unzip` and `python3` in the `ci` contract

Ship `unzip` and `python3` in the base image and admit both in the portable
`ci` contract, so composite actions that unpack zip release archives stop
dying with exit 127 and a runner missing either tool never advertises `ci`
(#72).

_Date: 2026-07-29; id:4aec608_

## Add `unzip` to the base runner image

Add `unzip` to the base runner image so containerized runners satisfy the
portable `ci` toolchain contract (gh, jq, git, curl, bash, tar, unzip, node,
docker) and no longer break actions that extract zip archives, such as
claude-code-action's setup-bun step (#59).

_Date: 2026-07-28; issue #59_

## Deliver the runner PAT through a one-use FIFO

Replace inspectable Docker `GITHUB_PAT` configuration with a one-use,
mode-0600 host FIFO consumed into non-exported supervisor memory; disable
unsafe automatic restart and require explicit owner acceptance before
rollout (#43).

_Date: 2026-07-28; issue #43_

## Redact proxy credentials in startup diagnostics

Redact proxy URL credentials from startup diagnostics while preserving the
original uppercase or lowercase proxy environment value for consumers (#42).

_Date: 2026-07-28; issue #42_

## Pin third-party test workflow actions

Pin every third-party action in the shell and Go test workflow to its reviewed
immutable commit SHA while retaining Renovate-readable major-version comments
(#39).

_Date: 2026-07-28; issue #39_

## Use a repository-relative security policy link

Replace the workstation-local security policy URL with a portable
repository-relative link.

_Date: 2026-07-28; issue #35_

## Make `RUNNER_EPHEMERAL` a tested lifecycle

Make `RUNNER_EPHEMERAL` a tested fresh-container lifecycle: `gha` now
supervises one-job `--rm` children, rejects ambiguous booleans and one-shot
credentials, keeps the Docker socket out of isolated jobs by default, and
integration-tests that writable-layer markers cannot cross generations or
survive a signalled controller shutdown (#33).

_Date: 2026-07-28; issue #33_

## Keep the dependency-update policy local

Preserve the shared dependency-update policy locally so Renovate can operate
without resolving an inaccessible private organization preset.

_Date: 2026-07-28; issue #31_

## Publish images from fixed hosted runners

Route this public repository's image publication through fixed hosted runners
so the persistent GCP group can deny all public-repository access.

_Date: 2026-07-28; id:18c300b_

## Fix Renovate preset resolution

Fix Renovate preset resolution by using the organization-local private preset.

_Date: 2026-07-27; issue #28_

## Correct the cloud-runner example

Correct the cloud-runner example to use provider-neutral `--runner-image` with
an immutable manifest digest and document the restricted-group, GCP ephemeral,
and DigitalOcean stable lifecycle requirements.

_Date: 2026-07-27; id:ba3658b_

## Dispatch the standalone `ci` command directly

Make the documented standalone container `ci` command dispatch directly to
fail-closed capability admission without touching registration inputs.

_Date: 2026-07-27; id:7375300_

## Define the attested `ci` runner image contract

Define one attested Verjson/Tequity `ci` runner image contract with fail-closed
case-insensitive capability admission, Node.js 24, pinned upstream checksums and
workflow actions, SBOM/provenance, and validated digest receipts.

_Date: 2026-07-27; id:196f1ae_
