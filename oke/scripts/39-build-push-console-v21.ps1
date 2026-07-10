# Build and push enlight-console:v21 from Windows (Docker Desktop must be running).
$ErrorActionPreference = "Stop"
$Image = "ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-console:v22"
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ConsoleDir = Join-Path $Root "console"

Write-Host "==> Build $Image"
Set-Location $ConsoleDir
docker build -t $Image .

Write-Host "==> Push $Image"
docker push $Image

Write-Host ""
Write-Host "OK. On Oracle Cloud Shell run:"
Write-Host @"

kubectl set image deployment/enlight-console console=$Image -n enlight-platform
kubectl delete pods -n enlight-platform -l app=enlight-console --force --grace-period=0
kubectl rollout status deployment/enlight-console -n enlight-platform --timeout=300s
curl -s http://144-24-100-85.nip.io/api/health

"@
