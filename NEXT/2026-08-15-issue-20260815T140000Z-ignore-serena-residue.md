---
date: 2026-08-15
id: 20260815T140000Z
title: Ignore Serena agent tooling residue
---

- Add `.serena/` to the agent tooling residue block in `.gitignore`, alongside `.tokensave/`, so an assistant's index directory cannot be committed and stops reporting the checkout as dirty.
