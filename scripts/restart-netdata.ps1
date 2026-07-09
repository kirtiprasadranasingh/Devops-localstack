#Requires -Version 5.1
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$NetdataDir = Join-Path $Root "netdata"

Write-Host "Restarting Netdata (Windows-friendly config)..." -ForegroundColor Cyan
Push-Location $NetdataDir
$ErrorActionPreference = "Continue"
docker compose down 2>&1 | Out-Null
docker rm -f netdata 2>&1 | Out-Null
docker compose up -d 2>&1 | ForEach-Object { Write-Host $_ }
Pop-Location

Write-Host ""
Write-Host "Waiting for Netdata (up to 3 minutes on first start)..." -ForegroundColor Yellow
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:19999/api/v1/info" -UseBasicParsing -TimeoutSec 5
        if ($r.StatusCode -eq 200) {
            Write-Host "OK: Netdata is up -> http://localhost:19999" -ForegroundColor Green
            exit 0
        }
    }
    catch {
        $status = docker inspect -f "{{.State.Status}}" netdata 2>$null
        Write-Host "  status=$status ..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}
Write-Host "Netdata still not ready. Check logs:" -ForegroundColor Red
Write-Host "  cd netdata && docker compose logs -f netdata"
