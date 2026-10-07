---
date: 2026-10-07
id: 20261007T151341Z
title: Pin artifact upload action in retention workflow
impact: patch
---

Update the GHCR retention workflow's actions/upload-artifact pin to v7.0.2.
Regenerate the container deployment review producer workflow from immutable
contract 737250a776a7990b5874e8f3a4c50e1c6d3d683c. All 23 shell-test workflow
steps passed, including the container deployment contract checks that verify the
generated review producer remains byte-identical to that pinned contract.
