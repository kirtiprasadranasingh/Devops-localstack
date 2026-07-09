#Requires -Version 5.1
# Frees port 5000 and starts one registry on kestra-net.

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$ErrorActionPreference = "Continue"

Write-Host "Fixing registry port 5000 conflict..." -ForegroundColor Cyan

$registryDir = Join-Path $Root "registry"
if (Test-Path $registryDir) {
    Push-Location $registryDir
    docker compose down 2>&1 | Out-Null
    Pop-Location
}

# Stop anything bound to port 5000 or using common registry names
docker rm -f registry local-registry 2>&1 | Out-Null
$on5000 = docker ps -aq --filter "publish=5000" 2>$null
if ($on5000) {
    $on5000 | ForEach-Object { docker rm -f $_ 2>&1 | Out-Null }
}

Write-Host "Port 5000 after cleanup:" -ForegroundColor DarkGray
docker ps --format "table {{.Names}}\t{{.Ports}}" | Select-String "5000"
if (-not (docker ps --format "{{.Ports}}" | Select-String "5000")) {
    Write-Host "    (none - port is free)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Starting full Kestra stack (includes registry on kestra-net)..." -ForegroundColor Cyan
Push-Location (Join-Path $Root "kestra")
docker compose up -d 2>&1 | ForEach-Object { Write-Host $_ }
Pop-Location

Start-Sleep -Seconds 5
Write-Host ""
Write-Host "Registry containers:" -ForegroundColor DarkGray
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | Select-String "5000|registry"

try {
    $r = Invoke-WebRequest -Uri "http://localhost:5000/v2/" -UseBasicParsing -TimeoutSec 8
    Write-Host "OK: Registry API at http://localhost:5000/v2/ ($($r.StatusCode))" -ForegroundColor Green
}
catch {
    Write-Host "WARN: Registry not responding yet. Run: cd D:\platform-poc\kestra && docker compose logs registry" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. Re-run Kestra pipeline (push uses registry:5000 on kestra-net)." -ForegroundColor Green
