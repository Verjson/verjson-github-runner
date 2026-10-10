---
date: 2026-10-10
id: 9f74c2a
title: Update Bubble Tea dependency to v2.1.0
impact: patch
---

Update `charm.land/bubbletea/v2` and its required transitive modules to v2.1.0. The runner dashboard keeps its existing API integration; tests exercise populated and empty views, alternate-screen rendering, logs, and restart behavior. `go test ./...`, `go vet ./...`, and `go build ./...` pass, so no application API adaptation was needed.
