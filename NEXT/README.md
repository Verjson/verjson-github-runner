# NEXT/ — changelog fragments

One file per log entry, validated against the **canonical changelog contract**
owned by [`Verjson/.github`](https://github.com/Verjson/.github)
([ADR 0038](https://github.com/Verjson/.github/tree/main/docs/decisions/0038-canonical-changelog-contract)).
Because no two pull requests edit the same file, the running log **cannot**
produce a merge conflict when several are in flight.

`NEXT/` is the sole store for unreleased entries. There is no committed
`NEXT.md` and no authored `CHANGELOG.md`: released history lives in immutable
`CHANGELOG/<version>.md` snapshots written by the contract's `release` command,
and any combined `CHANGELOG.md` is generated for display only.

## Adding an entry

In the **same commit** as a change that affects behaviour, pins, docs, or
config, add a new file:

```
NEXT/YYYY-MM-DD-issue-<identity>-<slug>.md
```

with front matter whose `date` and identity match the filename exactly:

```markdown
---
date: 2026-08-01
issue: 101
title: Short imperative title
---

One or two paragraphs: what changed, why, and issue/PR/ADR refs.
```

- **`issue:`** is a positive integer and is **unqualified — it means an issue in
  *this* repository**. Never borrow a number from another repository; cite
  foreign issues and ADRs in the body prose instead.
- **Use `issue:` whenever the work genuinely has an issue here.** The contract
  renders a `#n` back-link only for issue-form identities, so putting an `id` on
  issue-backed work silently drops that linkage with no validation error.
- **`id:`** replaces `issue:` for legitimately issue-less work: a UTC timestamp
  (`20260801T184500Z`) or 6–12 hexadecimal characters (a short commit SHA works
  well). Exactly one of `issue:` or `id:` is required.
- `slug` is lowercase words joined by hyphens. Entries render newest-first by
  metadata, not by filename allocation.
- Never edit another entry's file, and never reintroduce a shared, hand-edited
  changelog — that recreates the conflict structure this removes.

## Reading the log

```
scripts/render-next.sh          # renders every fragment, newest first
```

`scripts/render-next.sh` and `.github/workflows/changelog.yml` are **generated**
by `Verjson/.github scripts/gen-changelog-caller.sh` and pinned to one immutable
contract commit. Do not hand-edit either; regenerate them together so what you
render locally is what CI validates.
