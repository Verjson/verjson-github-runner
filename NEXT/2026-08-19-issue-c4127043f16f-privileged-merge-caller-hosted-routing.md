---
date: 2026-08-19
id: c4127043f16f
title: Regenerate the privileged-merge caller onto the hosted-routing contract
---

Regenerate both `.github/workflows/ai-privileged-merge.yml` and
`.github/workflows/ai-promotion-retry.yml` at the immutable
`f185ba0fcb1045b9dbe8c79e879c19a5b789ee4d` `Verjson/.github` contract. The
contract preserves this public repository's allowlisted disposable
GitHub-hosted route while synchronizing both terminal-merge entry points on
ADR 0118's admitted hosted-lane policy. The generated callers retain the
reviewed required-check identities and promotion-retry workflow set without a
repository-specific `runner_labels` override. Closes the remaining adoption
step named in Verjson/.github#676.

A controlled documentation-only pull request will verify this public caller's fixed
GitHub-hosted terminal route only if that continuation executes and merges the PR.
