#!/usr/bin/env bash
# Build the `gha` runner-manager binary into the repo root.
set -euo pipefail
cd "$(dirname "$0")"
( cd app && go build -o ../gha . )
echo "Built ./gha  —  run it with:  ./gha"
