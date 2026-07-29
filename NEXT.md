# Next

## 2026-07-29

- Keep the SIGTERM integration check running through expected supervisor
  termination so it can verify child-container cleanup, while rejecting
  unexpected supervisor exit statuses (#56).
- Report a typed, actionable timeout when PAT delivery cannot open its FIFO
  because no reader connects before the deadline, while preserving the
  underlying system error for diagnosis (#53).
- Report dashboard restart failures with actionable relaunch-via-setup guidance
  while preserving the runner refresh after a successful restart (#54).

## 2026-07-28

- Add `unzip` to the base runner image so containerized runners satisfy the
  portable `ci` toolchain contract (gh, jq, git, curl, bash, tar, unzip, node,
  docker) and no longer break actions that extract zip archives, such as
  claude-code-action's setup-bun step (#59).
- Replace inspectable Docker `GITHUB_PAT` configuration with a one-use,
  mode-0600 host FIFO consumed into non-exported supervisor memory; disable
  unsafe automatic restart and require explicit owner acceptance before
  rollout (#43).
- Redact proxy URL credentials from startup diagnostics while preserving the
  original uppercase or lowercase proxy environment value for consumers (#42).
- Preserve the shared dependency-update policy locally so Renovate can operate
  without resolving an inaccessible private organization preset.
- Pin every third-party action in the shell and Go test workflow to its reviewed
  immutable commit SHA while retaining Renovate-readable major-version comments
  (#39).
- Make `RUNNER_EPHEMERAL` a tested fresh-container lifecycle: `gha` now
  supervises one-job `--rm` children, rejects ambiguous booleans and one-shot
  credentials, keeps the Docker socket out of isolated jobs by default, and
  integration-tests that writable-layer markers cannot cross generations or
  survive a signalled controller shutdown (#33).
- Route this public repository's image publication through fixed hosted runners
  so the persistent GCP group can deny all public-repository access.
- Replace the workstation-local security policy URL with a portable
  repository-relative link.

## 2026-07-27

- Correct the cloud-runner example to use provider-neutral `--runner-image` with
  an immutable manifest digest and document the restricted-group, GCP ephemeral,
  and DigitalOcean stable lifecycle requirements.
- Make the documented standalone container `ci` command dispatch directly to
  fail-closed capability admission without touching registration inputs.
- Define one attested Verjson/Tequity `ci` runner image contract with fail-closed
  case-insensitive capability admission, Node.js 24, pinned upstream checksums and
  workflow actions, SBOM/provenance, and validated digest receipts.
- Fix Renovate preset resolution by using the organization-local private preset.
