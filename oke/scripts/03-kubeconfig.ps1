#Requires -Version 5.1
<#
.SYNOPSIS
  Configure kubectl for the OKE cluster.
#>

$ErrorActionPreference = "Stop"
$TfDir = Resolve-Path (Join-Path $PSScriptRoot "..\terraform")

Push-Location $TfDir
try {
    $clusterId = terraform output -raw cluster_id
    $region = terraform output -raw region
}
finally {
    Pop-Location
}

$kubeDir = Join-Path $env:USERPROFILE ".kube"
if (-not (Test-Path $kubeDir)) { New-Item -ItemType Directory -Path $kubeDir | Out-Null }
$kubeConfig = Join-Path $kubeDir "config"

function Find-OciExe {
    $oci = Get-Command oci -ErrorAction SilentlyContinue
    if ($oci) { return $oci.Source }
    foreach ($p in @(
        "$env:APPDATA\Python\Python313\Scripts\oci.exe",
        "$env:APPDATA\Python\Python312\Scripts\oci.exe",
        "C:\Python312\Scripts\oci.exe"
    )) {
        if (Test-Path $p) { return $p }
    }
    throw "oci not found — run: pip install oci-cli OR winget install Oracle.OCI-CLI"
}

$ociExe = Find-OciExe
Write-Host ""
Write-Host "==> Creating kubeconfig for cluster $clusterId" -ForegroundColor Cyan
& $ociExe ce cluster create-kubeconfig `
    --cluster-id $clusterId `
    --file $kubeConfig `
    --region $region `
    --token-version 2.0.0 `
    --kube-endpoint PUBLIC_ENDPOINT

if ($LASTEXITCODE -ne 0) { throw "oci create-kubeconfig failed" }

$env:KUBECONFIG = $kubeConfig
Write-Host ""
kubectl get nodes
Write-Host ""
Write-Host "Next: .\04-install-platform.ps1" -ForegroundColor Green
