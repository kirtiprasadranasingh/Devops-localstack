#Requires -Version 5.1
<#
.SYNOPSIS
  Check tools needed before OKE terraform apply.
#>

$ErrorActionPreference = "Continue"
$ok = $true

function Test-Cmd($name, $hint) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "  OK   $name" -ForegroundColor Green
        return $true
    }
    Write-Host "  MISS $name — $hint" -ForegroundColor Yellow
    return $false
}

Write-Host ""
Write-Host "OKE prerequisites" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Cmd "terraform" "Install: https://developer.hashicorp.com/terraform/install")) { $ok = $false }
if (-not (Test-Cmd "kubectl" "Install: https://kubernetes.io/docs/tasks/tools/")) { $ok = $false }
if (-not (Test-Cmd "helm" "Install: https://helm.sh/docs/intro/install/")) { $ok = $false }
if (-not (Test-Cmd "docker" "Docker Desktop required for image push")) { $ok = $false }

$ociOk = Test-Cmd "oci" "Install OCI CLI: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
if (-not $ociOk) { $ok = $false }

$tfvars = Join-Path $PSScriptRoot "..\terraform\terraform.tfvars"
if (Test-Path $tfvars) {
    Write-Host "  OK   terraform.tfvars exists" -ForegroundColor Green
}
else {
    Write-Host "  MISS terraform.tfvars — copy terraform.tfvars.example and set compartment_id" -ForegroundColor Yellow
    $ok = $false
}

Write-Host ""
if ($ok) {
    Write-Host "Ready for: .\02-terraform-apply.ps1" -ForegroundColor Green
}
else {
    Write-Host "Fix missing items above first." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "OCI CLI quick setup (after install):" -ForegroundColor DarkGray
    Write-Host "  oci setup config"
    Write-Host "  # You need: tenancy OCID, user OCID, region, API key fingerprint"
}
Write-Host ""
