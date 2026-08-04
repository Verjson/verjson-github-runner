---
date: 2026-08-04
issue: 113
title: Publish GitHub-verifiable image provenance
---

The trusted image publication workflow now creates GitHub artifact build provenance
attestations for every published base and kind digest without removing BuildKit SBOM,
provenance, or immutable digest receipts. A wired workflow contract locks the minimal
attestation permissions, main-only trigger, immutable official-action pins, and required
publication steps. Deployment verification must bind the full signer workflow identity
and `refs/heads/main`; the released updater does not yet do so, as tracked by
Verjson/verjson-cli-cloud#225.
