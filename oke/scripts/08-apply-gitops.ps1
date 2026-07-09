#Requires -Version 5.1
<#
.SYNOPSIS
  Register FastAPI ArgoCD Application (after 07-install-argocd.ps1).
#>

$ErrorActionPreference = "Stop"
$GitOps = Resolve-Path (Join-Path $PSScriptRoot "..\gitops\argocd")

Write-Host ""
Write-Host "==> Apply ArgoCD Application" -ForegroundColor Cyan
kubectl apply -f (Join-Path $GitOps "fastapi-minimal.yaml")

Write-Host ""
Write-Host "Note: image tag PLACEHOLDER in git must be updated after OCIR push," -ForegroundColor Yellow
Write-Host "or use 06-deploy-manifests.ps1 for direct kubectl deploy (phase 1)." -ForegroundColor Yellow
Write-Host ""
kubectl get applications -n argocd
