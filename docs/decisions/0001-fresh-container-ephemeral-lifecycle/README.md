# 0001 — Ephemeral means a fresh disposable job container

- **Date:** 2026-07-28
- **Issue:** Verjson/verjson-github-runner#33
- **Category:** runner isolation / credential lifecycle / Docker host authority
- **Status:** Accepted

## Context

The runner supported GitHub's `config.sh --ephemeral` flag while its Docker
container used `restart: unless-stopped`. GitHub accepted only one job per runner
registration, but Docker restarted the same writable layer and the entrypoint
registered it again. A marker outside the checkout could therefore survive into
the next job. The registration lifecycle was ephemeral; the execution
environment was not.

## Decision

`gha` ephemeral mode uses two container roles:

1. A long-lived **controller** holds the renewable GitHub registration
   credential and host Docker socket. It never registers as a runner and never
   executes workflow code.
2. For every generation, the controller removes any stale exact-name child and
   starts the immutable runner image through `docker run --rm`. The child
   registers with `--ephemeral`, executes at most one job, exits, and is deleted
   before the next generation.

The controller passes no Docker socket into a child unless the operator
explicitly selects the trusted Docker option. Supervisor mode rejects static
one-shot registration tokens because it must mint a fresh token for every
generation. `RUNNER_EPHEMERAL` accepts documented true and false values and
rejects ambiguous input. Direct ephemeral execution fails unless an external
orchestrator asserts `RUNNER_FRESH_CONTAINER=1`; a restart policy on one
container is never treated as fresh isolation.

## Verification

- Shell unit tests exercise boolean parsing, renewable-token admission,
  per-generation stale cleanup, socket exclusion, and shutdown cleanup.
- Go tests pin the manager's supervisor launch shape and explicit child-socket
  opt-in.
- A Docker integration fixture writes a marker into its root filesystem and
  fails if it already exists. The supervisor runs the same image twice; both
  generations pass. It then receives SIGTERM while attached to a blocking child
  and must stop/remove that child before exiting.

## Consequences

- Workflow state cannot persist through a job container's writable layer.
- The controller becomes a security-critical host component with Docker-root
  authority and must not execute caller code.
- Host-level state reachable through explicitly mounted volumes, Docker socket,
  metadata service, or network remains outside the writable-layer guarantee.
  Isolated lanes must keep those authorities absent or separately constrained.
- Persistent mode remains available and is explicitly lower isolation.
