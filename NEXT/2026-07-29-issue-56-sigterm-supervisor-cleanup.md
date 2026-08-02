---
date: 2026-07-29
issue: 56
title: Verify supervisor cleanup after expected SIGTERM
---

Keep the SIGTERM integration check running through expected supervisor
termination so it can verify child-container cleanup, while rejecting
unexpected supervisor exit statuses (#56).
