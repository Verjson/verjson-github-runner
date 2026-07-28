# Next

## 2026-07-28

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
