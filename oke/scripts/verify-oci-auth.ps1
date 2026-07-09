#Requires -Version 5.1
<#
.SYNOPSIS
  Verify Oracle API credentials before terraform apply.
#>

$ErrorActionPreference = "Continue"

function Find-Oci {
    $oci = Get-Command oci -ErrorAction SilentlyContinue
    if ($oci) { return $oci.Source }
    $paths = @(
        "$env:APPDATA\Python\Python313\Scripts\oci.exe",
        "$env:APPDATA\Python\Python312\Scripts\oci.exe",
        "C:\Python312\Scripts\oci.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$ociExe = Find-Oci
if (-not $ociExe) {
    Write-Host "OCI CLI not in PATH. Run:" -ForegroundColor Yellow
    Write-Host "  winget install Oracle.OCI-CLI"
    Write-Host "  pip install oci-cli"
    exit 1
}

Write-Host "Using: $ociExe" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Testing OCI authentication..." -ForegroundColor Cyan

$out = & $ociExe iam region list 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "OK: API key works" -ForegroundColor Green
    exit 0
}

Write-Host "FAIL: 401 NotAuthenticated" -ForegroundColor Red
Write-Host ""
Write-Host "Fix steps:" -ForegroundColor Yellow
Write-Host "  1. OCI Console -> Profile -> API Keys"
Write-Host "  2. Delete old key if fingerprint mismatch"
Write-Host "  3. Add API Key -> paste from:"
Write-Host "     $env:USERPROFILE\.oci\oci_api_key_public.pem"
Write-Host "     (or run: oci setup config)"
Write-Host "  4. Re-run this script"
Write-Host ""
Write-Host $out -ForegroundColor DarkGray
exit 1
