---
date: 2026-08-04
issue: 111
title: Complete the attested CI toolchain image
---

The published base now installs and admits the complete fixed organization CI toolchain,
including material runtime floors. A separately labeled multi-architecture PowerShell
variant layers on the exact base manifest digest and receives immutable digest receipts,
SBOM, and provenance. Shell and PowerShell launchers advertise accurate runtime
architecture labels, and supervisors fail closed by running a credential-free,
child-equivalent `ci`/`pwsh` candidate before minting registration credentials.
