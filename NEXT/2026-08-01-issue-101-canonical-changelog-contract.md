---
date: 2026-08-01
issue: 101
title: Adopt the canonical changelog contract
summary: This repository now uses the canonical Verjson changelog contract instead of the local fork of the tooling it had been running since #81. `scripts/render-next.sh` and `.github/workflows/changelog.yml` are generated from `Verjson/.github` at one pinned contract commit and delegate to that contract rather than reimplementing it, so the renderer and the validator can no longer drift apart silently. Every fragment moves to `NEXT/YYYY-MM-DD-issue-<identity>-<slug>.md` carrying `date`, `issue` or `id`, and `title` metadata that matches its filename, and the root `NEXT.md` pointer is deleted so `NEXT/` is the sole unreleased store.
---

This repository has been running a **local fork** of the changelog tooling since
#81 — a hand-copied bash concatenator in `scripts/render-next.sh`, plus 29
`NEXT/` fragments with no metadata front matter and no stable identity. A copy
drifts silently: it keeps rendering, so nothing ever fails, while it quietly
stops agreeing with the contract every other Verjson repository is validated
against.

`scripts/render-next.sh` and `.github/workflows/changelog.yml` are now
*generated* by `Verjson/.github scripts/gen-changelog-caller.sh` at pin
`1486d44d`, not hand-written — the renderer and the validator must agree on one
commit, and nothing fails loudly when they do not. The renderer no longer
implements rendering; it delegates to the pinned contract.

Every fragment becomes `NEXT/YYYY-MM-DD-issue-<identity>-<slug>.md` with
`date` / `issue` (or `id`) / `title` metadata matching its filename. Identity
came from each entry's introducing commit and that pull request's GraphQL
`closingIssuesReferences` — never from body prose, which cites plenty of foreign
issues and ADRs. The root `NEXT.md` pointer is deleted: `NEXT/` is the sole
unreleased store, and a pointer file that CI does not validate is one more
surface to drift.

Implements [Verjson/.github ADR 0038](https://github.com/Verjson/.github/tree/main/docs/decisions/0038-canonical-changelog-contract)
(`Verjson/.github#286`, handoff `Verjson/.github#249`). Fixes #101.
