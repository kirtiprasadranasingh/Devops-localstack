#Requires -Version 5.1
<#
.SYNOPSIS
  Stop Platform PoC stack (Netdata, Kestra, Dokploy, registry).
#>

$ErrorActionPreference = "Continue"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

$stacks = @(
    @{ Name = "Console"; Dir = Join-Path $Root "console" },
    @{ Name = "Netdata"; Dir = Join-Path $Root "netdata" },
    @{ Name = "Kestra"; Dir = Join-Path $Root "kestra" },
    @{ Name = "Dokploy"; Dir = Join-Path $Root "dokploy" },
    @{ Name = "Registry"; Dir = Join-Path $Root "registry" }
)

Write-Host "Stopping DevOps Local Stack..." -ForegroundColor Cyan

foreach ($s in $stacks) {
    if (Test-Path $s.Dir) {
        Write-Host "  $($s.Name)..." -ForegroundColor DarkGray
        Push-Location $s.Dir
        docker compose down 2>&1 | Out-Null
        Pop-Location
    }
}

Write-Host "Done." -ForegroundColor Green
