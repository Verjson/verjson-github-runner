# 0010 — Admit general runners by Docker bridge routing

- **Date:** 2026-08-26
- **Status:** Accepted

## Context

[`Verjson/.github#1093`](https://github.com/Verjson/.github/issues/1093) recorded a
heterogeneous shared pool: `gha-general-1` could use the host Docker daemon but could not
route from its runner container to service containers on `172.17.0.0/16`. Canonical
database-backed CI deliberately resolves a service container's bridge address because
host loopback and the bridge gateway are not portable across this fleet. The defective
host therefore produced random red builds whenever GitHub selected it.

The existing `ci` admission proves Docker CLI and daemon health, not the network path
between sibling containers. A label-only inventory reconciler cannot measure that path,
and changing canonical CI to tolerate an unreachable database would turn a loud
infrastructure failure into missing test coverage.

## Decision

Before consuming a registration credential, every runner advertising the exact,
case-insensitive `general` label must start a disposable sibling on Docker's default
bridge and reach its bridge IP from the prospective runner container. Failure prevents
registration, so an unhealthy host cannot attach `general`.

The sibling uses the same already-local runner image by immutable Docker image ID. An
explicit `RUNNER_BRIDGE_PROBE_IMAGE` is allowed only as `sha256:<64 lowercase hex>`;
mutable tags and pullable repository references fail closed. The probe receives no
GitHub credential, uses a fixed non-runner entrypoint, validates Docker's returned IPv4
address before constructing a URL, bypasses ambient proxies, has bounded retries, and is
removed on either result.

The organization may quarantine a failing host by removing only `general`, leaving the
registration available for maintenance. Restoring that label requires a successful
admission receipt on the repaired launch configuration.

## Consequences

- General runners cannot accept work when sibling bridge routing is broken.
- Admission adds one short-lived local container and a bounded local HTTP probe at runner
  startup; it performs no network pull.
- Hosts that override their container hostname must provide the immutable local image ID
  explicitly.
- This protects new registrations and restarts. Live runners deployed from older images
  remain an operational rollout concern and must stay quarantined until upgraded and
  re-admitted.
