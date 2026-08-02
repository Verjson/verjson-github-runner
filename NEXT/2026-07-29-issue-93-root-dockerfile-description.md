---
date: 2026-07-29
issue: 93
title: Correct the README's account of the root Dockerfile
---

The README called the root `Dockerfile` a pre-`images/` leftover kept only for backward
compat, which invited operators to dismiss the file their own hosts run: `setup.sh` and
`docker-compose.yml` both build it, and `Dockerfile.pwsh` now layers on it. The note now
describes the actual split — root `Dockerfile` for the persistent compose/`setup.sh` lane,
`images/base.Dockerfile` for the portable published image carrying the `ci` contract.
Fixes #93.
