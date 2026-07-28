# 0002 — Fresh-container lifecycle for ephemeral runners

- **Status:** Proposed — human security review required
- **Date:** 2026-07-28
- **Category:** Security-sensitive runner isolation and registration credentials
- **Issue:** [Verjson/verjson-github-runner#33](https://github.com/Verjson/verjson-github-runner/issues/33)
- **Builds on:** [ADR-0001](../0001-attested-ci-runner-contract/README.md)

## Context

GitHub's `--ephemeral` option limits a registration to one job, but it does not
destroy the container that hosts the runner. Combining that option with Docker
`--restart unless-stopped` restarts the same container and writable layer after
the runner exits. That can retain state written outside the checked-out
repository and can repeatedly attempt registration inside the old container.

The previous documentation treated one-job registration as if it also proved
fresh container state. ADR-0001 requires consumers to preserve job-clean
isolation but does not define the container lifecycle that establishes it. This
decision refines that boundary without changing ADR-0001's accepted image and
capability contract.

## Decision

Supported launchers implement two explicit modes:

1. Ephemeral mode accepts only `RUNNER_EPHEMERAL=1` or `true`, passes
   `--ephemeral` to GitHub registration, launches the container with Docker
   `--rm`, and installs no restart policy. Completion, crash, and shutdown all
   attempt de-registration. Restoring capacity requires a new `docker run`, so a
   later job receives a different container identity and writable layer.
2. Persistent mode accepts `0`, `false`, or an empty value and retains
   `--restart unless-stopped`. It is labeled as lower isolation and is unsuitable
   for untrusted pull-request code.

Every other `RUNNER_EPHEMERAL` value fails before token minting or registration.
An external supervisor may remain long-lived, but it may only replenish
ephemeral capacity by creating a new disposable container. It must not restart
or adopt a completed job container.

Inside each container, the entrypoint supervises the pinned Actions runner
wrapper → helper → `Runner.Listener`/`Runner.Worker` topology as one dedicated
process group. Shutdown sends TERM to the whole group, waits five seconds, and
sends a group-wide KILL if needed. De-registration begins only after the group is
gone. This avoids treating the wrapper PID as if it were the actual listener.

Registration and removal sources are captured into non-exported supervisor
variables and unset from the imported container environment. The registration
token is cleared after `config.sh`, and the scheduled Listener/Worker tree is
started through a credential-scrubbing environment boundary. This applies to
the manager, shell, PowerShell, and Compose launch paths because they all use the
same image entrypoint.

The `gha` manager and both setup scripts construct the lifecycle flags. Compose
exposes separate services; ephemeral use is supported only through
`docker compose --profile ephemeral run --rm runner-ephemeral`.

## Evidence required before rollout

- Unit tests for explicit true, false, empty, and invalid parsing.
- Entrypoint tests for token refresh, registration, de-registration, normal exit,
  runner crash, and topology-faithful process-group shutdown.
- Explicit Listener and Worker environment tests proving token, PAT, mint/remove
  command, cloud, Docker auth, and broad credential variables are absent.
- Docker integration tests proving different container IDs, an observable and
  asserted marker-absence verdict, crash removal without a restart loop,
  shutdown removal, and persistent-mode compatibility.
- Independent security review and explicit human acceptance of the exact
  implementation head.

## Consequences

- Ephemeral capacity is not automatically replenished by Docker. A provider or
  reconciler must deliberately create the next clean container.
- A crashed one-job runner disappears instead of retrying registration in the
  compromised writable layer.
- Shutdown latency can increase by up to five seconds when a runner process
  ignores TERM; it is then killed before removal credentials are used.
- Operators needing stable trusted capacity may keep persistent mode, accepting
  its cross-restart state-retention boundary.
- This decision does not authorize deployment, runner-group access changes, or
  execution of untrusted workflows.

## Rejected alternatives

- **`--ephemeral` with `--restart unless-stopped`** reuses the writable layer and
  can loop through reconfiguration.
- **Best-effort workspace deletion** cannot prove removal of state elsewhere in
  the container filesystem.
- **Restarting the same stopped container** preserves its identity and layer; it
  is not a fresh-job boundary.
