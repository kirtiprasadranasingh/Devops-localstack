#Requires -Version 5.1
<#
.SYNOPSIS
  Master OKE build script for DevOps Local Stack.
.EXAMPLE
  .\build-oke.ps1 -Step terraform
  .\build-oke.ps1 -Step all
#>

param(
    [ValidateSet("setup", "verify", "terraform", "kubeconfig", "ingress", "images", "deploy", "argocd", "all")]
    [string]$Step = "all"
)

$Scripts = $PSScriptRoot

function Run([string]$name, [string]$script) {
    Write-Host ""
    Write-Host "========== $name ==========" -ForegroundColor Cyan
    & $script
    if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" }
}

$steps = @{
    setup      = { Run "Setup" (Join-Path $Scripts "00-setup.ps1") }
    verify     = { Run "Verify OCI" (Join-Path $Scripts "verify-oci-auth.ps1") }
    terraform  = { Run "Terraform" (Join-Path $Scripts "02-terraform-apply.ps1") }
    kubeconfig = { Run "Kubeconfig" (Join-Path $Scripts "03-kubeconfig.ps1") }
    ingress    = { Run "Ingress" (Join-Path $Scripts "04-install-platform.ps1") }
    images     = { Run "Push images" (Join-Path $Scripts "05-push-images.ps1") }
    deploy     = { Run "Deploy" (Join-Path $Scripts "06-deploy-manifests.ps1") }
    argocd     = { Run "ArgoCD" (Join-Path $Scripts "07-install-argocd.ps1") }
}

if ($Step -eq "all") {
  foreach ($s in @("verify", "terraform", "kubeconfig", "ingress", "images", "deploy")) {
    & $steps[$s]
  }
}
else {
  & $steps[$Step]
}

Write-Host ""
Write-Host "DevOps Local Stack OKE build step complete." -ForegroundColor Green
