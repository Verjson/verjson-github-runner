---
date: 2026-07-29
issue: 78
title: Stamp the isolation-supervisor contract label on the base image
---

`images/base.Dockerfile` now sets the OCI config label
`com.verjson.gha-runner.isolation-supervisor="1"`, and every kind image inherits it via
`FROM ${BASE_IMAGE}`. Isolated-mode admission in `@verjson/cli-cloud`
(`runner-image-contract`) previously had to fall back to a hard-coded digest allowlist,
which meant each new image publish needed a CLI release before it could be deployed in
isolated mode; the label lets images self-describe the contract instead. The value
versions the supervisor admission contract and consumers fail closed on values they do
not recognize, so bump it only on an incompatible change. SECURITY.md's Image
Supply-Chain Integrity section documents the label. Fixes #78.
