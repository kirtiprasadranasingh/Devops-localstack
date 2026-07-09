#Requires -Version 5.1
# One-time cleanup after removing Docker-in-Docker from Kestra stack.

Write-Host "Cleaning up old kestra-dind..." -ForegroundColor Cyan
docker rm -f kestra-dind 2>&1 | Out-Null
docker volume rm kestra_dind-storage 2>&1 | Out-Null

Write-Host "Restarting Kestra stack..." -ForegroundColor Cyan
Push-Location (Join-Path $PSScriptRoot "..\kestra")
docker compose down 2>&1 | Out-Null
docker compose up -d 2>&1 | ForEach-Object { Write-Host $_ }
Pop-Location

Start-Sleep -Seconds 10
docker ps --format "table {{.Names}}\t{{.Status}}" | Select-String "kestra|registry"

Write-Host ""
Write-Host "Done. Kestra should be at http://localhost:8085" -ForegroundColor Green
Write-Host "Re-import kestra/flows/dagger-dokploy-pipeline.yaml in Kestra UI." -ForegroundColor Yellow
