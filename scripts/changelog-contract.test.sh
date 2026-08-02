#!/usr/bin/env bash
# Asserts this repository still satisfies the canonical changelog contract
# (Verjson/.github ADR 0038) rather than a local re-implementation of it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
contract_ref="1486d44db0668d61354815c12bdbfc9d53fbeca4"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/verjson-changelog/$contract_ref"
contract="$cache_dir/changelog.py"
renderer="$root/scripts/render-next.sh"
validation_workflow="$root/.github/workflows/changelog.yml"

if [ ! -f "$contract" ]; then
  mkdir -p "$cache_dir"
  tmp="$(mktemp "$cache_dir/.changelog.XXXXXX")"
  curl -fsSL \
    "https://raw.githubusercontent.com/Verjson/.github/$contract_ref/scripts/changelog.py" \
    -o "$tmp"
  mv "$tmp" "$contract"
fi

python3 "$contract" validate --repo-root "$root"
echo "ok - canonical validation accepts every fragment in NEXT/"

# The renderer and the validator must resolve to the same contract commit: a
# split pin renders locally what CI never checks.
for file in "$renderer" "$validation_workflow"; do
  grep -q "$contract_ref" "$file"
done
grep -q "changelog-validate.yml@$contract_ref" "$validation_workflow"
echo "ok - render and validation automation share one immutable pin"

# This repository has no release workflow at all, so there is no third pin to
# keep in step. Adding one is a separate decision, not a migration side effect.
if [ -e "$root/.github/workflows/release.yml" ]; then
  echo "FAIL - a release workflow appeared without being pinned by this test" >&2
  exit 1
fi
echo "ok - no unpinned release automation was introduced"

# The renderer must delegate rather than re-implement rendering. This repo
# shipped a hand-copied bash concatenator since #81; that is the drift being
# prevented. It must also be executable: core.fileMode=false hides a 100644
# blob locally and CI then fails with exit 126.
grep -q 'render-next --repo-root' "$renderer"
[ -x "$renderer" ]
echo "ok - the renderer delegates to the pinned contract and is executable"

rendered_next="$("$renderer")"
grep -q '^## Adopt the canonical changelog contract$' <<<"$rendered_next"
grep -q '^## Define the attested `ci` runner image contract$' <<<"$rendered_next"
echo "ok - canonical rendering includes the expected unreleased fragments"

# The generated renderer takes no arguments; a caller passing one must fail
# loudly rather than silently render the whole log.
if "$renderer" --repo-root "$root" >/dev/null 2>&1; then
  echo "FAIL - the renderer accepted an argument it does not honour" >&2
  exit 1
fi
echo "ok - the renderer rejects arguments instead of ignoring them"

# Identity is not decoration: only issue-form entries render a `#n` back-link,
# so a fragment silently demoted to an `id` loses its release linkage with no
# validation error.
grep -q '^_Date: 2026-08-01; issue #101_$' <<<"$rendered_next"
grep -q '^_Date: 2026-07-29; id:d333a3f_$' <<<"$rendered_next"
echo "ok - issue identities render a back-link and issue-less ones do not fake one"

# Metadata, not filename allocation, orders the log.
[ "$(grep -n '^## Adopt the canonical changelog contract$' <<<"$rendered_next" | cut -d: -f1)" \
  -lt "$(grep -n '^## Define the attested `ci` runner image contract$' <<<"$rendered_next" | cut -d: -f1)" ]
echo "ok - rendering order follows metadata instead of slug allocation"

# NEXT/ is the sole unreleased store: no shared prepend-only file may come back.
if [ -e "$root/NEXT.md" ] || [ -e "$root/CHANGELOG.md" ]; then
  echo "FAIL - an authored aggregate changelog reappeared at the repository root" >&2
  exit 1
fi
echo "ok - no authored aggregate changelog exists at the repository root"

# v0.1.0 was tagged before any changelog file existed here, so migration must
# not have invented released history. CHANGELOG/ fills from the first
# contract-driven release forward.
[ -z "$(python3 "$contract" render-released --repo-root "$root")" ]
echo "ok - migration fabricated no released history"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

new_fixture() {
  local dir
  dir="$(mktemp -d "$fixture_root/case.XXXXXX")"
  mkdir -p "$dir/NEXT"
  printf '%s' "$dir"
}

fixture="$(new_fixture)"
for slug in first second; do
  cat >"$fixture/NEXT/2026-08-01-issue-101-$slug.md" <<'EOF'
---
date: 2026-08-01
issue: 101
title: Duplicate
---

Body.
EOF
done
if python3 "$contract" validate --repo-root "$fixture" 2>"$fixture/error"; then
  echo "FAIL - duplicate issue identity was accepted" >&2
  exit 1
fi
grep -q 'duplicate identity issue:101' "$fixture/error"
echo "ok - duplicate issue identities are rejected"

fixture="$(new_fixture)"
cat >"$fixture/NEXT/2026-08-01-issue-101-wrong-date.md" <<'EOF'
---
date: 2026-07-31
issue: 101
title: Wrong date
---

Body.
EOF
if python3 "$contract" validate --repo-root "$fixture" 2>"$fixture/error"; then
  echo "FAIL - mismatched filename metadata was accepted" >&2
  exit 1
fi
grep -q 'does not match' "$fixture/error"
echo "ok - malformed fragment metadata is rejected"

fixture="$(new_fixture)"
cat >"$fixture/NEXT/2026-08-01-legacy-uncanonical-name.md" <<'EOF'
---
date: 2026-08-01
issue: 101
title: Legacy name
---

Body.
EOF
if python3 "$contract" validate --repo-root "$fixture" 2>"$fixture/error"; then
  echo "FAIL - a pre-migration fragment filename was accepted" >&2
  exit 1
fi
grep -q 'does not follow the canonical contract' "$fixture/error"
echo "ok - pre-migration fragment filenames cannot come back"

fixture="$(new_fixture)"
mkdir -p "$fixture/CHANGELOG"
cat >"$fixture/NEXT/2026-08-01-issue-101-release.md" <<'EOF'
---
date: 2026-08-01
issue: 101
title: Release
---

Body.
EOF
printf 'immutable\n' >"$fixture/CHANGELOG/v0.1.0.md"
git -C "$fixture" init -q
git -C "$fixture" config user.name Test
git -C "$fixture" config user.email test@example.com
git -C "$fixture" add .
git -C "$fixture" commit -qm initial
if python3 "$contract" release --repo-root "$fixture" --version v0.1.0 2>"$fixture/error"; then
  echo "FAIL - released snapshot overwrite was accepted" >&2
  exit 1
fi
grep -q 'already exists' "$fixture/error"
[ "$(cat "$fixture/CHANGELOG/v0.1.0.md")" = 'immutable' ]
echo "ok - released snapshots cannot be overwritten"
