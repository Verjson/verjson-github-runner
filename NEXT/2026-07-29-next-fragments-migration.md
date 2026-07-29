# Migrate the running log to per-entry fragments — 2026-07-29

Split the prepend-only `NEXT.md` into one file per entry under `NEXT/`, rendered
newest-first by `scripts/render-next.sh`, matching the org reference shape in
`Verjson/.github`. A shared, prepend-only log makes every concurrent PR collide
on the same first lines: PR #74 needed a rebase round purely for that, and a
conflicted PR is worse than noisy — GitHub runs no `pull_request` workflows at
all on a conflicting head, so PR #76 sat with zero CI signal until the log was
untangled. A file per entry can never conflict. Refs #77.
