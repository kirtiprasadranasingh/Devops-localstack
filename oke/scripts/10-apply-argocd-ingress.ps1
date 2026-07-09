#Requires -Version 5.1
<#
.SYNOPSIS
  Apply ArgoCD path ingress (/gitops) on the same hostname as the console.
.PARAMETER IngressHost
  Same host as path-a-deploy (e.g. 144-24-100-85.nip.io).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$IngressHost
)

$ErrorActionPreference = "Stop"
$OkeRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ingress = Get-Content (Join-Path $OkeRoot "ingress\argocd-paths.yaml") -Raw
$ingress = $ingress.Replace("PLACEHOLDER_HOST", $IngressHost)
$staging = Join-Path $env:TEMP "argocd-paths.yaml"
Set-Content -Path $staging -Value $ingress -NoNewline
kubectl apply -f $staging
Write-Host "ArgoCD UI: http://${IngressHost}/gitops" -ForegroundColor Green
