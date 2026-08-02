---
date: 2026-07-29
issue: 88
title: PowerShell runner variant, as a separate tag
---

`verjson-agents` ships two installers but only the bash suite runs in CI: no available
runner can execute `tests/install.test.ps1`, so a test in it stayed silently broken for
months (Verjson/verjson-agents#43). The persistent-lane image built by `docker compose`
and `setup.sh` — the root `Dockerfile` — installs `ca-certificates curl jq git sudo tar
gzip` and no PowerShell, so the step could not be enabled.

New `Dockerfile.pwsh` layers `pwsh` on that image: `ARG PWSH_VERSION=7.6.4` (current LTS)
with per-arch `PWSH_SHA256_AMD64`/`PWSH_SHA256_ARM64` checked by `sha256sum -c` against
Microsoft's published `hashes.sha256`, installed to `/opt/microsoft/powershell/7` with a
`/usr/local/bin/pwsh` symlink — the same pin-and-verify shape `images/base.Dockerfile`
uses for `gh` and Node, and deliberately not the Microsoft apt repository, which would let
the installed version float with build date.

It is a **separate tag** rather than an addition to the default image: PowerShell costs
~270 MB (1.36 GB → 1.63 GB measured) and only some lanes need it, so the runner everyone
else builds stays lean — the alternative #88 itself proposed. It is also deliberately not
under `images/`: those build the portable `ci` contract image that `entrypoint.sh` admits
against, and PowerShell is excluded from that contract by agreement with Tequity (#29).
Adding it there would widen a shared contract; adding it here does not. Fixes #88.
