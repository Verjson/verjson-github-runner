# 0002 — Deliver launcher PATs through a one-use FIFO

- **Date:** 2026-07-28
- **Issue:** Verjson/verjson-github-runner#43
- **Category:** credential transport / Docker host authority
- **Status:** Accepted pending explicit owner rollout acceptance

## Context

The shell, PowerShell, Compose, and Go manager launch paths configured
`GITHUB_PAT=<value>` on `docker run`. Although workflow descendants did not
inherit that variable, Docker retained it in container metadata for the
container lifetime. Host users with Docker authority could retrieve it through
inspect, and command instrumentation could capture it from launcher argv.

The supervisor needs a renewable credential in memory to mint a fresh
registration token for every job and a fresh removal token during orderly
shutdown. A one-shot GitHub registration token cannot satisfy that lifecycle.

## Decision

Launchers create a private host temporary directory and a `github-pat` FIFO with
mode 0600. Docker bind-mounts that directory at `/run/gha-secrets` and configures
only the non-secret FIFO pathname. After detached startup, the launcher writes
the PAT once. The entrypoint validates that the path is a mode-0600 FIFO, reads
one line into a non-exported shell variable, and unlinks the FIFO before any
registration request.

The launcher removes the temporary directory after delivery. Failed or
interrupted delivery removes the container or transport; a destroyed FIFO
cannot be replayed. The PAT is never placed in Docker environment values,
command arguments, image metadata, logs, or a persistent volume.

Automatic Docker restart is disabled because supervisor memory and its one-use
transport do not survive a process or host restart. Operators must relaunch
through an authorized launcher. During one process lifetime the supervisor
continues to mint fresh registration tokens and, on orderly shutdown, a fresh
removal token.

Compose remains supported by requiring the operator to create a private
directory with a mode-0600 `github-pat` FIFO, set `GITHUB_PAT_DIR`, start
Compose, write the PAT once, and remove the directory after consumption.

## Verification

- Shell tests cover mode validation, one-use consumption, destruction, and
  replay rejection.
- Go tests assert the PAT is absent from Docker argv/configured environment and
  cover destroyed-transport delivery.
- Static launcher contracts cover shell, PowerShell, manager, Compose, and the
  no-restart constraint.

## Consequences

- A host principal with Docker authority can still control the supervisor
  process and must remain trusted, but Docker metadata no longer retains the
  renewable credential.
- Unexpected supervisor termination cannot mint a removal token. GitHub may
  temporarily show an offline runner until normal reconciliation removes it.
- Rollout requires independent security review and explicit owner acceptance.
