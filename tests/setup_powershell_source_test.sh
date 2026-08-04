#!/usr/bin/env bash
# shellcheck disable=SC2016 # PowerShell variables below are intentional literals.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
setup="${root}/setup.ps1"

grep -Fq '[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture' "${setup}"
grep -Fq '"X64" { $archLabel = "x64" }' "${setup}"
grep -Fq '"Arm64" { $archLabel = "ARM64" }' "${setup}"
grep -Fq '$defaultLabels = "self-hosted,linux,$archLabel,docker"' "${setup}"
grep -Fq '$labels       = Read-Default "Labels (comma-separated)" $defaultLabels' "${setup}"
grep -Fq 'else { return $v }' "${setup}"

if grep -Fq 'Read-Default "Labels (comma-separated)" "self-hosted,linux,x64,docker"' "${setup}"; then
  echo "setup.ps1 still hard-codes x64 as its label default" >&2
  exit 1
fi
