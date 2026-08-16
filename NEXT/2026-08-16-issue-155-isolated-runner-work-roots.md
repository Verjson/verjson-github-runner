---
date: 2026-08-16
issue: 155
title: Isolate concurrent runner work roots
---

Derive each self-hosted runner's job workspace from its unique runner name so
concurrent checkouts cannot corrupt another runner's Git index or worktree.
