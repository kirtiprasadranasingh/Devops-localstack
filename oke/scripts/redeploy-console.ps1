#Requires -Version 5.1
<#
.SYNOPSIS
  Build + push console image on Windows. Apply to OKE (needs kubectl) OR print Cloud Shell steps.
.EXAMPLE
  .\redeploy-console.ps1 -Tag v8
  .\redeploy-console.ps1 -Tag v8 -SkipKubectl
#>
param(
    [string]$Tag = "v8",
    [string]$OcirNamespace = "bmitpaosivqx",
    [string]$Region = "ap-mumbai-1",
    [string]$IngressHost = "144-24-100-85.nip.io",
    [switch]$SkipKubectl
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$ConsoleImage = "${Region}.ocir.io/${OcirNamespace}/enlight-console:${Tag}"
$PublicBase = "http://${IngressHost}"
$KestraPublic = "http://kestra.${IngressHost}"

Write-Host "==> Build console ($ConsoleImage)" -ForegroundColor Cyan
Push-Location (Join-Path $Root "console")
docker build --no-cache -t $ConsoleImage .
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
Pop-Location

Write-Host ""
Write-Host "==> Push to OCIR" -ForegroundColor Cyan
docker push $ConsoleImage
if ($LASTEXITCODE -ne 0) {
    Write-Host "Push failed. Login first:" -ForegroundColor Red
    Write-Host "  docker login ${Region}.ocir.io"
    Write-Host "  Username: ${OcirNamespace}/<oci-username>"
    Write-Host "  Password: OCI auth token"
    throw "docker push failed"
}

Write-Host ""
Write-Host "Image pushed: $ConsoleImage" -ForegroundColor Green

if ($SkipKubectl) {
    Write-Host ""
    Write-Host "=== Paste these in OCI Cloud Shell ===" -ForegroundColor Yellow
    Write-Host @"
kubectl set image deployment/enlight-console console=$ConsoleImage -n enlight-platform
kubectl set env deployment/enlight-console -n enlight-platform `
  MODE=oke `
  KESTRA_FLOW_ID=oke-deploy-simple `
  KESTRA_NAMESPACE=main `
  KESTRA_URL=http://kestra.enlight-platform.svc.cluster.local:8080 `
  KESTRA_PUBLIC_URL=$KestraPublic `
  PUBLIC_BASE_URL=$PublicBase `
  APP_HEALTH_URL=http://fastapi.enlight-staging.svc.cluster.local/health
kubectl patch deployment enlight-console -n enlight-platform -p '{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"console\",\"imagePullPolicy\":\"Always\"}]}}}}'
kubectl rollout restart deployment/enlight-console -n enlight-platform
kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s
kubectl get pods -n enlight-platform -l app=enlight-console -o wide
curl -s http://$IngressHost/api/info
"@
    exit 0
}

Write-Host ""
Write-Host "==> Apply on cluster (kubectl)" -ForegroundColor Cyan
kubectl set image deployment/enlight-console console=$ConsoleImage -n enlight-platform
if ($LASTEXITCODE -ne 0) {
    Write-Host "kubectl failed — cluster not reachable from this PC." -ForegroundColor Yellow
    Write-Host "Re-run with: .\redeploy-console.ps1 -Tag $Tag -SkipKubectl" -ForegroundColor Yellow
    Write-Host "Then paste the Cloud Shell commands it prints." -ForegroundColor Yellow
    exit 1
}

kubectl set env deployment/enlight-console -n enlight-platform `
  MODE=oke `
  KESTRA_FLOW_ID=oke-deploy-simple `
  KESTRA_NAMESPACE=main `
  KESTRA_URL=http://kestra.enlight-platform.svc.cluster.local:8080 `
  KESTRA_PUBLIC_URL=$KestraPublic `
  PUBLIC_BASE_URL=$PublicBase `
  APP_HEALTH_URL=http://fastapi.enlight-staging.svc.cluster.local/health

kubectl patch deployment enlight-console -n enlight-platform --type='json' -p='[{"op":"replace","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"Always"}]' 2>$null
kubectl rollout restart deployment/enlight-console -n enlight-platform
kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s

Write-Host ""
Write-Host "Verify:" -ForegroundColor Green
Write-Host "  curl $PublicBase/api/info"
Write-Host "  Open $PublicBase  (Ctrl+F5)"
