# Next

## 2026-07-28

- Preserve the shared dependency-update policy locally so Renovate can operate
  without resolving an inaccessible private organization preset.

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
