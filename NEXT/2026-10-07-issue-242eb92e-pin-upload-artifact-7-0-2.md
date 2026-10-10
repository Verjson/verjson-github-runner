---
date: 2026-10-07
id: 242eb92e
impact: patch
title: Pin upload-artifact to v7.0.2
---

Pin both `actions/upload-artifact` steps in the GHCR retention workflow to v7.0.2. The GHCR retention policy's 29 tests and its workflow shell contract pass; no source adaptation was required.
