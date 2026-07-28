#!/bin/sh
set -eu
if [ -e /job-generation-marker ]; then
  echo "marker leaked from an earlier job generation" >&2
  exit 1
fi
touch /job-generation-marker
echo "fresh writable layer"
