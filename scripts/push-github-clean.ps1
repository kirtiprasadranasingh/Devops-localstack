#Requires -Version 5.1
<#
.SYNOPSIS
  Push to GitHub without secrets in git history (orphan branch).
.EXAMPLE
  .\scripts\push-github-clean.ps1
#>
$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path (Join-Path $PSScriptRoot ".."))

$github = "https://github.com/kirtiprasadranasingh/Devops-localstack.git"

Write-Host "==> Ensure kestra/.env is NOT tracked" -ForegroundColor Cyan
if (Test-Path "kestra/.env") {
    Copy-Item "kestra/.env" "kestra/.env.local.backup" -Force
    Write-Host "Backed up local kestra/.env to kestra/.env.local.backup"
}
git rm --cached -f kestra/.env 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { $global:LASTEXITCODE = 0 }

Write-Host "==> Create clean orphan branch (no secret history)" -ForegroundColor Cyan
git checkout --orphan github-clean

Write-Host "==> Stage safe files only" -ForegroundColor Cyan
git add .gitignore
git add README.md
if (Test-Path docs) { git add docs/ }
if (Test-Path oke) { git add oke/ }
if (Test-Path kestra/flows) { git add kestra/flows/ }
if (Test-Path kestra/.env.example) { git add kestra/.env.example }
if (Test-Path kestra/docker-compose.yml) { git add kestra/docker-compose.yml }
if (Test-Path console/backend) { git add console/backend/ }
if (Test-Path console/frontend/src) { git add console/frontend/src/ }
if (Test-Path console/frontend/index.html) { git add console/frontend/index.html }
if (Test-Path console/frontend/package.json) { git add console/frontend/package.json }
if (Test-Path console/frontend/vite.config.js) { git add console/frontend/vite.config.js }
if (Test-Path console/Dockerfile) { git add console/Dockerfile }
if (Test-Path console/frontend/dist) { git add console/frontend/dist/ }
if (Test-Path scripts) { git add scripts/ }
if (Test-Path sample-app) { git add sample-app/ }
if (Test-Path dokploy) { git add dokploy/ }
if (Test-Path netdata) { git add netdata/ }
if (Test-Path registry) { git add registry/ }
if (Test-Path start-platform.bat) { git add start-platform.bat }

git reset HEAD kestra/.env 2>$null
git reset HEAD oke/terraform/terraform.tfvars 2>$null

$status = git status --short
if ($null -eq $status -or $status.Count -eq 0) {
    $statusLine = git status --short | Out-String
    if ([string]::IsNullOrWhiteSpace($statusLine)) {
        throw "Nothing staged. Check paths."
    }
}
git status --short

git commit -m "Enlight Lab OKE platform - console, Kestra flows, GitOps (no secrets)"

Write-Host "==> Push to GitHub (force replaces remote main)" -ForegroundColor Cyan
git remote add github $github 2>$null
git push github HEAD:main --force

Write-Host ""
Write-Host "DONE. Restore your branch with: git checkout main" -ForegroundColor Green
Write-Host "GitHub: $github" -ForegroundColor Green
