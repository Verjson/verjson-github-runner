# Build the runner images on pull requests — 2026-07-29

New workflow `.github/workflows/image-build-check.yml` builds `images/base.Dockerfile`,
the four kind images, and the root `Dockerfile` on `pull_request`, amd64 only and
build-only (nothing pushed, no registry credential). Until now neither Dockerfile was
built before merge: `publish-images.yml` triggers on push to `main` and tags, and
`test.yml` runs only the shell and Go suites, so a broken image change — bad base
codename, renamed apt package, checksum drift — first surfaced as a published `:latest`
that hosts pull.

Kinds are built with `BASE_IMAGE` pointed at the base built in the same job, matching how
`publish-images.yml` wires them, so a base change that breaks a kind fails on the PR. The
workflow is path-filtered to image inputs; `test.yml` deliberately keeps no paths filter,
so every PR still reports at least one check to the merge gate. Fixes #79.
