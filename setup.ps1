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
$GITHUB_PAT = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($patSecure))
if ([string]::IsNullOrWhiteSpace($GITHUB_PAT)) { throw "A PAT is required (org: admin:org / repo: repo)." }

$namesInput = Read-Default "Runner name(s), comma-separated" "ci-runner-01"
$labels     = Read-Default "Labels (comma-separated)" "self-hosted,linux,x64,docker"

Write-Host "Building image ($image)..." -ForegroundColor Cyan
docker build -t $image .
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

foreach ($raw in $namesInput.Split(",")) {
    $name = $raw.Trim()
    if ($name -eq "") { continue }
    $container = "gha-$name"
    Write-Host "Starting runner '$name' (container: $container)" -ForegroundColor Cyan
    docker rm -f $container 2>$null | Out-Null
    docker run -d `
        --name $container `
        --restart unless-stopped `
        -e GITHUB_URL=$GITHUB_URL `
        -e GITHUB_PAT=$GITHUB_PAT `
        -e RUNNER_NAME=$name `
        -e RUNNER_LABELS=$labels `
        $image | Out-Null
}

Write-Host "`nRunners are up:" -ForegroundColor Green
docker ps --filter "name=gha-" --format "table {{.Names}}`t{{.Status}}"
Write-Host "`nFollow logs:   docker logs -f gha-<name>   (wait for 'Listening for Jobs')"
Write-Host "Stop one:      docker rm -f gha-<name>"
Write-Host ("Target it in a workflow:  runs-on: [ {0} ]" -f ($labels -replace ',', ', '))
