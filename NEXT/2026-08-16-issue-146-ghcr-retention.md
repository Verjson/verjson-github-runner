---
date: 2026-08-16
issue: 146
title: Add read-only GHCR retention planning
---

Define the destructive package-retention boundary in ADR 0006 and add a strictly
read-only, auditable inventory plan for `ghcr.io/verjson/gha-runner`. The planner
validates OCI evidence, preserves newly untagged versions through a fresh age floor, and
identifies provisional policy candidates; pruning remains blocked on separate explicit
authorization and complete deployment, review, and per-mutation evidence contracts.
