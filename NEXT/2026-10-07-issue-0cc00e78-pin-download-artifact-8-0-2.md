---
date: 2026-10-07
id: 0cc00e78
impact: patch
title: Pin download-artifact to v8.0.2
---

Pin all three `actions/download-artifact` steps in the runner deployment review producer to v8.0.2. The generated consumer contract remains blocked until the upstream workflow contract is refreshed; see https://github.com/VerJSON/.github/issues/1719.
