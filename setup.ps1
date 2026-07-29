#!/usr/bin/env pwsh
#
# Interactive setup for one or more Dockerized GitHub Actions self-hosted runners.
# Windows (PowerShell) equivalent of setup.sh. Requires Docker Desktop.
#
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$image = "gha-runner:local"

function Read-Default($prompt, $default) {
    $v = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default } else { return $v }
}

Write-Host "=== GitHub self-hosted runner setup ===" -ForegroundColor Cyan

$GITHUB_URL = Read-Host "GitHub URL (org e.g. https://github.com/Verjson, or repo URL)"
if ([string]::IsNullOrWhiteSpace($GITHUB_URL)) { throw "GitHub URL is required." }

$patSecure = Read-Host "GitHub PAT (input hidden)" -AsSecureString
$patBstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($patSecure)
try {
    $GITHUB_PAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($patBstr)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($patBstr)
}
if ([string]::IsNullOrWhiteSpace($GITHUB_PAT)) { throw "A PAT is required (org: admin:org / repo: repo)." }

$namesInput   = Read-Default "Runner name(s), comma-separated" "ci-runner-01"
$labels       = Read-Default "Labels (comma-separated)" "self-hosted,linux,x64,docker"
$runnerGroup  = Read-Default "Runner group (org runners only; Default for repo)" "Default"
$runnerWork   = Read-Default "Work folder" "_work"

Write-Host "Building image ($image)..." -ForegroundColor Cyan
docker build -t $image .
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

foreach ($raw in $namesInput.Split(",")) {
    $name = $raw.Trim()
    if ($name -eq "") { continue }
    $container = "gha-$name"
    Write-Host "Starting runner '$name' (container: $container)" -ForegroundColor Cyan
    docker rm -f $container 2>$null | Out-Null
    $transportDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gha-pat-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $transportDir | Out-Null
    $patFifo = Join-Path $transportDir "github-pat"
    $delivered = $false
    if (-not $IsLinux) { throw "One-use PAT FIFO transport requires Linux containers on a Linux Docker host." }
    & mkfifo -m 600 $patFifo
    try {
        docker run -d `
            --name $container `
            --restart no `
            --mount "type=bind,src=$transportDir,dst=/run/gha-secrets" `
            -e GITHUB_URL=$GITHUB_URL `
            -e GITHUB_PAT_FIFO=/run/gha-secrets/github-pat `
            -e RUNNER_NAME=$name `
            -e RUNNER_LABELS=$labels `
            -e RUNNER_GROUP=$runnerGroup `
            -e RUNNER_WORKDIR=$runnerWork `
            $image | Out-Null
        [System.IO.File]::WriteAllText($patFifo, "$GITHUB_PAT`n")
        $delivered = $true
    } finally {
        if (-not $delivered) { docker rm -f $container 2>$null | Out-Null }
        Remove-Item -Recurse -Force $transportDir -ErrorAction SilentlyContinue
    }
}
$GITHUB_PAT = $null

Write-Host "`nRunners are up:" -ForegroundColor Green
docker ps --filter "name=gha-" --format "table {{.Names}}`t{{.Status}}"
Write-Host "`nFollow logs:   docker logs -f gha-<name>   (wait for 'Listening for Jobs')"
Write-Host "Stop one:      docker rm -f gha-<name>"
Write-Host "Restart one:   re-run setup; one-use credential delivery disables Docker auto-restart"
Write-Host ("Target it in a workflow:  runs-on: [ {0} ]" -f ($labels -replace ',', ', '))
