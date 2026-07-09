#Requires -Version 5.1
<#
.SYNOPSIS
  First-time setup: OCI CLI check + create terraform.tfvars.
.EXAMPLE
  .\00-setup.ps1
#>

$ErrorActionPreference = "Stop"
$TfDir = Resolve-Path (Join-Path $PSScriptRoot "..\terraform")
$TfVars = Join-Path $TfDir "terraform.tfvars"
$Example = Join-Path $TfDir "terraform.tfvars.example"

Write-Host ""
Write-Host "DevOps Local Stack — OKE setup" -ForegroundColor Cyan
Write-Host ""

# Refresh PATH for newly installed OCI CLI
$ociPaths = @(
    "$env:LOCALAPPDATA\Programs\Oracle\OCI",
    "$env:ProgramFiles\Oracle\oci-cli",
    "$env:USERPROFILE\bin"
)
foreach ($p in $ociPaths) {
    if (Test-Path $p) { $env:Path = "$p;$env:Path" }
}

$oci = Get-Command oci -ErrorAction SilentlyContinue
if (-not $oci) {
    Write-Host "OCI CLI not found. Install with:" -ForegroundColor Yellow
    Write-Host "  winget install Oracle.OCI-CLI"
    Write-Host ""
    Write-Host "Then open a NEW terminal and run this script again." -ForegroundColor Yellow
    exit 1
}
Write-Host "OK: OCI CLI at $($oci.Source)" -ForegroundColor Green

$config = Join-Path $env:USERPROFILE ".oci\config"
if (-not (Test-Path $config)) {
    Write-Host ""
    Write-Host "OCI not configured yet. Running: oci setup config" -ForegroundColor Yellow
    Write-Host "You need from cloud.oracle.com -> Profile:" -ForegroundColor DarkGray
    Write-Host "  - Tenancy OCID, User OCID, Region, API key" -ForegroundColor DarkGray
    Write-Host ""
    oci setup config
}

if (Test-Path $TfVars) {
    Write-Host ""
    Write-Host "terraform.tfvars already exists." -ForegroundColor Green
    Get-Content $TfVars
    $overwrite = Read-Host "Overwrite? (y/N)"
    if ($overwrite -ne "y" -and $overwrite -ne "Y") {
        Write-Host "Next: .\02-terraform-apply.ps1" -ForegroundColor Green
        exit 0
    }
}

Write-Host ""
Write-Host "Enter your OCI compartment OCID" -ForegroundColor Cyan
Write-Host "(Console -> Identity -> Compartments -> copy OCID)" -ForegroundColor DarkGray
$compartment = Read-Host "compartment_id"

$region = Read-Host "region [ap-mumbai-1]"
if (-not $region) { $region = "ap-mumbai-1" }

@"
compartment_id = "$compartment"
region         = "$region"
cluster_name   = "devopslocalstack"
kubernetes_version = "v1.30.1"
node_ocpus     = 2
node_memory_gbs = 12
node_count     = 1
"@ | Set-Content -Path $TfVars -Encoding UTF8

Write-Host ""
Write-Host "Created $TfVars" -ForegroundColor Green
Write-Host "Next: .\02-terraform-apply.ps1" -ForegroundColor Green
