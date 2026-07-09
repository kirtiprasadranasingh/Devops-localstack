#Requires -Version 5.1
<#
.SYNOPSIS
  Rename project folder from platform-poc to enlight-devops-stack.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\rename-project.ps1
#>

$ErrorActionPreference = "Stop"
$current = Resolve-Path (Join-Path $PSScriptRoot "..")
$parent = Split-Path $current -Parent
$target = Join-Path $parent "enlight-devops-stack"

if ($current.Path -like "*enlight-devops-stack") {
    Write-Host "Already named enlight-devops-stack." -ForegroundColor Green
    exit 0
}

if (Test-Path $target) {
    Write-Host "Target already exists: $target" -ForegroundColor Red
    exit 1
}

Write-Host "Renaming:" -ForegroundColor Cyan
Write-Host "  From: $current"
Write-Host "  To:   $target"
Rename-Item -Path $current -NewName "enlight-devops-stack"
Write-Host ""
Write-Host "Done. Reopen D:\enlight-devops-stack in Cursor." -ForegroundColor Green
