---
date: 2026-08-30
issue: 194
impact: patch
title: Add Bubblewrap to standard runner images
---

Install Bubblewrap through the shared runner base so every published variant, including
`gha-runner-pwsh`, provides a root-owned, non-writable `/usr/bin/bwrap` at version 0.9.0
or newer. Every final amd64 and arm64 variant now executes a descriptor-bound image
contract that rejects symlinks, mutable ancestry, unsafe ownership or modes, and path
replacement before publication.
