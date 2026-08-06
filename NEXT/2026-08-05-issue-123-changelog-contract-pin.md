---
date: 2026-08-05
issue: 123
title: "chore(changelog): move the contract pin to f12dca7"
---

The changelog contract pin moves from `1486d44d` to `f12dca7`, and the three canonical
adopter artifacts — `.github/workflows/changelog.yml`, `scripts/render-next.sh` and
`scripts/changelog-contract.test.sh` — are regenerated from
`Verjson/.github/scripts/gen-changelog-caller.sh` at that commit. Seven `NEXT/` fragments
gain a `summary:` line, because at this pin a released snapshot carries the release note
rather than the whole diary entry, and those seven led with the problem they solved instead
of what they shipped.

The pin matters more than a routine bump because it changes what a release writes into
`CHANGELOG/<version>.md`, which is immutable once cut (Verjson/.github ADR 0059). A
released entry now renders `title` plus the lead paragraph, with an optional `summary:`
overriding the lead for the released form only (Verjson/.github#426); `render-next.sh`
with no arguments still renders the full body. Cutting a release on the old engine would
have frozen all 38 entries in full — the shape that gave `Verjson/verjson-ai` a 174 KB
changelog for 62 entries.

Both ways of reading that released form before it freezes were also broken until this pin,
which is why they were exercised here rather than assumed:
`scripts/render-next.sh --as-released` used to exit 2 in an adopter repository because the
generated renderer refused every argument (Verjson/.github#443), and the CI release-note
preview never reached an adopter at all, existing only in `generated-artifacts.yml`
(Verjson/.github#449). The pin also brings correct reading of a quoted title by the
generated contract test (Verjson/.github#436) and identities that render as written
(Verjson/.github#434).

This repository has no `release.yml` caller, so there is no release workflow to re-pin, and
a tree-wide sweep found no repo-local assertion hardcoding the old contract pin. It stays
on `changelog-validate.yml` rather than the shared `generated-artifacts.yml`, and leaves
`adr-index` off: the generator emits a `changelog-validate.yml` caller and the contract
test greps for exactly that string, and this repository has no `scripts/gen-adr-index.sh`
for an opted-in index check to run (Verjson/.github#437).

Fixes #123.
