#Requires -Version 5.1

<#

.SYNOPSIS

  Path A — deploy to EXISTING OKE cluster (no Terraform). Reuses enlight-staging FastAPI.

.PARAMETER ConsoleImage

  Full OCIR image for enlight-console.

.PARAMETER IngressHost

  Hostname for ingress (devopslocalstack.enlightlab.com or 144-24-100-85.nip.io).

.PARAMETER PublicBaseUrl

  Base URL shown in console links (http://144-24-100-85.nip.io).

#>

param(

    [string]$ConsoleImage = "ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v7",

    [string]$IngressHost = "144-24-100-85.nip.io",

    [string]$PublicBaseUrl = ""

)



$ErrorActionPreference = "Stop"

$OkeRoot = Resolve-Path (Join-Path $PSScriptRoot "..")

if (-not $PublicBaseUrl) {

    if ($IngressHost -match "nip\.io") { $PublicBaseUrl = "http://$IngressHost" }

    else { $PublicBaseUrl = "https://$IngressHost" }

}

$KestraPublic = "http://kestra.$IngressHost"

$Staging = Join-Path $env:TEMP "enlight-path-a"



if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }

New-Item -ItemType Directory -Path $Staging | Out-Null



Write-Host "==> Namespace" -ForegroundColor Cyan

kubectl apply -f (Join-Path $OkeRoot "manifests\00-namespace.yaml")



Write-Host "==> Kestra RBAC" -ForegroundColor Cyan

kubectl apply -f (Join-Path $OkeRoot "manifests\31-kestra-rbac.yaml")



Write-Host "==> Kestra" -ForegroundColor Cyan

kubectl apply -f (Join-Path $OkeRoot "manifests\30-kestra.yaml")



Write-Host "==> Console" -ForegroundColor Cyan

$console = Get-Content (Join-Path $OkeRoot "manifests\20-console.yaml") -Raw

$console = $console.Replace("PLACEHOLDER_OCIR_CONSOLE", $ConsoleImage)

$console = $console.Replace("PLACEHOLDER_PUBLIC_BASE_URL", $PublicBaseUrl)

$console = $console.Replace("PLACEHOLDER_KESTRA_PUBLIC_URL", $KestraPublic)

Set-Content (Join-Path $Staging "20-console.yaml") -Value $console -NoNewline

kubectl apply -f (Join-Path $Staging "20-console.yaml")



Write-Host "==> Ingress host: $IngressHost" -ForegroundColor Cyan

$ingress = Get-Content (Join-Path $OkeRoot "ingress\devopslocalstack-paths.yaml") -Raw

$ingress = $ingress.Replace("PLACEHOLDER_HOST", $IngressHost)

Set-Content (Join-Path $Staging "paths-ingress.yaml") -Value $ingress -NoNewline

kubectl apply -f (Join-Path $Staging "paths-ingress.yaml")



$kestraIng = Get-Content (Join-Path $OkeRoot "ingress\kestra-host.yaml") -Raw

$kestraIng = $kestraIng.Replace("PLACEHOLDER_HOST", $IngressHost)

Set-Content (Join-Path $Staging "kestra-host.yaml") -Value $kestraIng -NoNewline

kubectl apply -f (Join-Path $Staging "kestra-host.yaml")



$appIng = Get-Content (Join-Path $OkeRoot "ingress\app-host.yaml") -Raw

$appIng = $appIng.Replace("PLACEHOLDER_HOST", $IngressHost)

Set-Content (Join-Path $Staging "app-host.yaml") -Value $appIng -NoNewline

kubectl apply -f (Join-Path $Staging "app-host.yaml")



kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s

kubectl rollout status deployment/kestra -n enlight-platform --timeout=300s



Write-Host ""

Write-Host "Test:" -ForegroundColor Green

Write-Host "  $PublicBaseUrl"

Write-Host "  $KestraPublic"

Write-Host "  http://app.$IngressHost"

kubectl get pods,svc,ingress -n enlight-platform

