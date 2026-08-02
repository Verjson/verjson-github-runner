---
date: 2026-08-02
issue: 105
title: Install canonical privileged merge caller
---

Install the generated thin caller for the organization trusted merge workflow so green adversarial reviews can complete matched-head squash merges without waiting for a second human reviewer. The caller exposes only `ORG_ADMIN_TOKEN` and inherits the provenance, CI, hold, and head-SHA checks defined by Verjson/.github ADRs 0036, 0042, 0043, and 0044.