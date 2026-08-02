---
date: 2026-07-29
id: d333a3f
title: Document `general` as the provider-neutral lane label
---

The runner docs described kind labels (`rust`, `node`, …) and the `ci` contract, but never
the lane axis, so the shared persistent pool was reachable only through provider-named
labels (`GCP`, `gce`). That made a cloud move a code change: every consumer's `runs-on`
would have had to be rewritten, or DigitalOcean runners mislabelled `GCP`. The README now
documents `general` and `isolated` as the two lanes, states that provider and host names
are never lane labels, and repeats that `isolated`'s companion labels (`untrusted-pr`,
`ephemeral`, `no-host-docker`) are enforced security properties rather than description.
`SECURITY.md` drops the provider name from the runner-group reference for the same reason.

Runner-side part of #80; the org variable flip and DigitalOcean provisioning are tracked
in `Verjson/.github` and `Verjson/verjson-cli-cloud`.
