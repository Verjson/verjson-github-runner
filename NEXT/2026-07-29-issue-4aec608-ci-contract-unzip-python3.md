---
date: 2026-07-29
id: 4aec608
title: Ship `unzip` and `python3` in the `ci` contract
---

Ship `unzip` and `python3` in the base image and admit both in the portable
`ci` contract, so composite actions that unpack zip release archives stop
dying with exit 127 and a runner missing either tool never advertises `ci`
(#72).
