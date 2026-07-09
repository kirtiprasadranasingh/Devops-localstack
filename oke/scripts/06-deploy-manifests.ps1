#Requires -Version 5.1
<#
.SYNOPSIS
  Deploy workloads and ingress to OKE.
#>

$ErrorActionPreference = "Stop"
$OkeRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TfDir = Join-Path $OkeRoot "terraform"
$ManifestDir = Join-Path $OkeRoot "manifests"
$IngressFile = Join-Path $OkeRoot "ingress\devopslocalstack.yaml"
$Staging = Join-Path $env:TEMP "enlight-oke-manifests"

Push-Location $TfDir
try {
    $fastapiImage = "$(terraform output -raw ocir_fastapi_repo):latest"
    $consoleImage = "$(terraform output -raw ocir_console_repo):latest"
}
finally {
    Pop-Location
}

if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging | Out-Null

Get-ChildItem $ManifestDir -Filter "*.yaml" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content.Replace("PLACEHOLDER_OCIR_FASTAPI", $fastapiImage)
    $content = $content.Replace("PLACEHOLDER_OCIR_CONSOLE", $consoleImage)
    Set-Content -Path (Join-Path $Staging $_.Name) -Value $content -NoNewline
}

Write-Host ""
Write-Host "==> Apply manifests" -ForegroundColor Cyan
kubectl apply -f $Staging

Write-Host ""
Write-Host "==> Apply ingress" -ForegroundColor Cyan
kubectl apply -f $IngressFile

Write-Host ""
Write-Host "==> Rollout status" -ForegroundColor Cyan
kubectl rollout status deployment/fastapi-minimal -n enlight-platform --timeout=180s
kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=180s

Write-Host ""
kubectl get pods,svc,ingress -n enlight-platform
Write-Host ""
$ip = kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath="{.status.loadBalancer.ingress[0].ip}" 2>$null
if ($ip) {
    Write-Host "Test (after DNS or hosts file):" -ForegroundColor Green
    Write-Host "  http://devopslocalstack.enlightlab.com  (via IP $ip)"
    Write-Host "  http://app.devopslocalstack.enlightlab.com/health"
}
