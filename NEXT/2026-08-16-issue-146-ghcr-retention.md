---
date: 2026-08-16
issue: 146
title: Add fail-closed GHCR retention planning
---

Define the destructive package-retention boundary in ADR 0006 and add a read-only,
auditable dry run for `ghcr.io/verjson/gha-runner`. A separately gated manual path can
apply only a revalidated, bounded plan after deployment and rollback digests are
protected; this change does not authorize or perform package deletion.
