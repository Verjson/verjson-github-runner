# NEXT/ — changelog fragments

One file per log entry. Because no two PRs edit the same file, the running log
**cannot** produce a merge conflict when several PRs are in flight — the
friction that made the prepend-only `NEXT.md` costly once this repo started
fanning out concurrent work.

## Adding an entry

In the **same commit** as a change that affects behaviour, pins, docs, or
config, add a new file:

```
NEXT/YYYY-MM-DD-<short-slug>.md
```

The file is one entry, starting with an H1 title that ends in the date:

```markdown
# Short imperative title — 2026-07-29

One or two paragraphs: what changed, why, and issue/PR/ADR refs.
```

- `YYYY-MM-DD` is the date the entry lands. Fragments render **newest first**,
  so a later date sorts above an earlier one; same-day entries sort by slug in
  reverse-alphabetical order (rarely matters — pick distinct slugs and it does
  not).
- Never edit another entry's file, and never reintroduce a shared, hand-edited
  changelog — that recreates the conflict structure this removes.

## Reading the log

```
scripts/render-next.sh          # concatenates all fragments, newest first
```

Nothing renders to a committed combined file: keeping the rendered log out of
git is what guarantees zero conflicts.
