#Requires -Version 5.1
<#
.SYNOPSIS
  Provision OKE cluster + OCIR repos via Terraform.
#>

$ErrorActionPreference = "Stop"
$TfDir = Resolve-Path (Join-Path $PSScriptRoot "..\terraform")

Write-Host ""
Write-Host "==> Terraform init" -ForegroundColor Cyan
Push-Location $TfDir
try {
    terraform init
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

    Write-Host ""
    Write-Host "==> Terraform plan" -ForegroundColor Cyan
    terraform plan -out=tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }

    Write-Host ""
    Write-Host "Review the plan above. Continue with apply? (y/N)" -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Host "Aborted." -ForegroundColor DarkGray
        exit 0
    }

    Write-Host ""
    Write-Host "==> Terraform apply (10-20 min)" -ForegroundColor Cyan
    terraform apply tfplan
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }

    Write-Host ""
    Write-Host "==> Outputs" -ForegroundColor Green
    terraform output
    Write-Host ""
    Write-Host "Next: .\03-kubeconfig.ps1" -ForegroundColor Green
}
finally {
    Pop-Location
}
