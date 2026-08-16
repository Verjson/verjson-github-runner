# 0009 — Isolate work roots by runner identity

- **Date:** 2026-08-16
- **Issue:** [Verjson/verjson-github-runner#155](https://github.com/Verjson/verjson-github-runner/issues/155)
- **Category:** runner topology / checkout isolation
- **Status:** Accepted

## Context

Issue #155 records concurrent self-hosted runner processes mutating the same
repository checkout under a shared `_work` directory. GitHub runner names are
unique within their registration scope, while the configured work-folder value
was previously passed through unchanged to every process.

## Decision

Treat `RUNNER_WORKDIR` as a parent directory and append the validated
`RUNNER_NAME` before registration. Emit a startup admission receipt containing
the derived root. Reject runner names that cannot safely form one path segment,
and hold an exclusive filesystem lock for that root for the runner process's
lifetime so replacement overlap fails closed.

## Consequences

Different runner processes cannot share a Git index or checkout even when their
deployment supplies the same work-folder parent. Existing cached workspaces move
one level deeper on the first launch after adoption and can be reclaimed after
the old runners stop. The work-parent filesystem must implement `flock`.
