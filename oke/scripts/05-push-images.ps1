#Requires -Version 5.1
<#
.SYNOPSIS
  Build and push FastAPI + Console images to OCIR.
#>

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$TfDir = Resolve-Path (Join-Path $PSScriptRoot "..\terraform")

Push-Location $TfDir
try {
    $region = terraform output -raw region
    $ns = terraform output -raw ocir_namespace
    $fastapiRepo = terraform output -raw ocir_fastapi_repo
    $consoleRepo = terraform output -raw ocir_console_repo
}
finally {
    Pop-Location
}

$ocirHost = "$region.ocir.io"
Write-Host ""
Write-Host "OCIR login required." -ForegroundColor Cyan
Write-Host "Username format: $ns/<your-oci-username>" -ForegroundColor DarkGray
Write-Host "Password: Auth token from OCI Console -> User Settings -> Auth Tokens" -ForegroundColor DarkGray
Write-Host ""
docker login $ocirHost

Write-Host ""
Write-Host "==> Build & push FastAPI" -ForegroundColor Cyan
Push-Location (Join-Path $Root "sample-app\fastapi-minimal")
docker build -t "${fastapiRepo}:latest" .
docker push "${fastapiRepo}:latest"
Pop-Location

Write-Host ""
Write-Host "==> Build & push Console" -ForegroundColor Cyan
Push-Location (Join-Path $Root "console")
docker build -t "${consoleRepo}:latest" .
docker push "${consoleRepo}:latest"
Pop-Location

Write-Host ""
Write-Host "Images pushed:" -ForegroundColor Green
Write-Host "  ${fastapiRepo}:latest"
Write-Host "  ${consoleRepo}:latest"
Write-Host ""
Write-Host "Next: .\06-deploy-manifests.ps1" -ForegroundColor Green
