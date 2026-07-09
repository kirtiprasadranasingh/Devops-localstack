#Requires -Version 5.1
<#
.SYNOPSIS
  Start the full Platform PoC stack (registry, Dokploy, Kestra, Netdata).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\start-platform.ps1
#>

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "    OK: $Message" -ForegroundColor Green
}

function Write-WarnMsg([string]$Message) {
    Write-Host "    WARN: $Message" -ForegroundColor Yellow
}

function Invoke-ComposeUp([string]$Name, [string]$Dir) {
    Write-Step "Starting $Name"
    Push-Location $Dir
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & docker compose up -d 2>&1 | ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        $text = ($output | Out-String)

        if ($exitCode -ne 0) {
            if ($text -match "port is already allocated|Bind for") {
                Write-WarnMsg "$Name may already be running (port in use). Continuing."
            }
            else {
                Write-Host $text -ForegroundColor DarkGray
                throw "docker compose failed in $Dir (exit $exitCode)"
            }
        }
        else {
            if ($text.Trim()) {
                Write-Host $text -ForegroundColor DarkGray
            }
            Write-Ok "$Name started"
        }
    }
    finally {
        Pop-Location
    }
}

function Wait-ForUrl([string]$Url, [int]$Seconds = 90) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
                return $true
            }
        }
        catch {
            Start-Sleep -Seconds 3
        }
    }
    return $false
}

Write-Host ""
Write-Host "DevOps Local Stack - startup" -ForegroundColor White
Write-Host "Root: $Root" -ForegroundColor DarkGray

Write-Step "Checking Docker"
$ErrorActionPreference = "Continue"
& docker info *> $null
$dockerOk = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = "Stop"
if (-not $dockerOk) {
    Write-Host "Docker is not running. Start Docker Desktop, then run this script again." -ForegroundColor Red
    exit 1
}
Write-Ok "Docker is running"

Write-Step "Checking Docker TCP API (port 2375)"
$ErrorActionPreference = "Continue"
$tcpOk = $false
try {
    $tcp = Test-NetConnection -ComputerName localhost -Port 2375 -WarningAction SilentlyContinue
    $tcpOk = $tcp.TcpTestSucceeded
}
catch { }
$ErrorActionPreference = "Stop"
if (-not $tcpOk) {
    Write-WarnMsg "Docker daemon is not exposed on tcp://localhost:2375"
    Write-Host "    Kestra pipeline needs this. In Docker Desktop:" -ForegroundColor Yellow
    Write-Host "    Settings -> General -> Expose daemon on tcp://localhost:2375 without TLS" -ForegroundColor Yellow
    Write-Host "    Then restart Docker Desktop and run this script again." -ForegroundColor Yellow
}
else {
    Write-Ok "Docker TCP API reachable on port 2375"
}
$envExample = Join-Path $Root "kestra\.env.example"
$envFile = Join-Path $Root "kestra\.env"
if (-not (Test-Path $envFile)) {
    if (Test-Path $envExample) {
        Copy-Item $envExample $envFile
        Write-WarnMsg "Created kestra\.env from example - edit tokens/IDs if needed"
    }
    else {
        Write-WarnMsg "kestra\.env missing - Kestra may need manual configuration"
    }
}
else {
    Write-Ok "kestra\.env exists"
}

Invoke-ComposeUp "Dokploy (port 3000)" (Join-Path $Root "dokploy")
Write-Step "Waiting for Dokploy UI (up to 90s)"
if (Wait-ForUrl "http://localhost:3000" 90) {
    Write-Ok "Dokploy reachable at http://localhost:3000"
}
else {
    Write-WarnMsg "Dokploy not responding yet - wait a minute and refresh browser"
}

Write-Step "Removing old kestra-dind (replaced by Docker Desktop TCP API)"
$ErrorActionPreference = "Continue"
docker rm -f kestra-dind 2>&1 | Out-Null
docker volume rm kestra_dind-storage 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

Write-Step "Freeing port 5000 (stop duplicate registry if any)"
$ErrorActionPreference = "Continue"
$regDir = Join-Path $Root "registry"
if (Test-Path $regDir) {
    Push-Location $regDir
    docker compose down 2>&1 | Out-Null
    Pop-Location
}
docker rm -f registry local-registry 2>&1 | Out-Null
$on5000 = docker ps -aq --filter "publish=5000" 2>$null
if ($on5000) { $on5000 | ForEach-Object { docker rm -f $_ 2>&1 | Out-Null } }
$ErrorActionPreference = "Stop"

Write-Step "Starting Kestra + registry on kestra-net (ports 8085, 5000)"
Invoke-ComposeUp "Kestra stack" (Join-Path $Root "kestra")
Write-Step "Waiting for Kestra UI (up to 120s)"
if (Wait-ForUrl "http://localhost:8085" 120) {
    Write-Ok "Kestra reachable at http://localhost:8085"
}
else {
    Write-WarnMsg "Kestra not responding yet - first start can take 2-3 minutes"
}

Write-Step "Starting Netdata (port 19999) - can take 1-3 min on Windows"
Invoke-ComposeUp "Netdata" (Join-Path $Root "netdata")
Write-Host "    Waiting for Netdata health (up to 180s)..." -ForegroundColor DarkGray
$netdataReady = $false
$netDeadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $netDeadline) {
    if (Wait-ForUrl "http://localhost:19999/api/v1/info" 8) {
        $netdataReady = $true
        break
    }
    $state = docker inspect -f "{{.State.Status}}" netdata 2>$null
    if ($state -eq "exited" -or $state -eq "dead") {
        Write-WarnMsg "Netdata container stopped ($state). Run: .\scripts\restart-netdata.ps1"
        break
    }
    Write-Host "    ... still starting (container: $state)" -ForegroundColor DarkGray
}
if ($netdataReady) {
    Write-Ok "Netdata reachable at http://localhost:19999"
}
else {
    Write-WarnMsg "Netdata not ready yet - other services are up. Try: .\scripts\restart-netdata.ps1"
}

Write-Step "Building & starting Enlight Platform Console (port 3100)"
Invoke-ComposeUp "Platform Console" (Join-Path $Root "console")
Write-Step "Waiting for Console (up to 120s)"
if (Wait-ForUrl "http://localhost:3100/api/health" 120) {
    Write-Ok "Console reachable at http://localhost:3100"
}
else {
    Write-WarnMsg "Console not ready - run: cd console && docker compose up -d --build"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  DevOps Local Stack - ready" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  CONSOLE   http://localhost:3100   (prod: devopslocalstack.enlightlab.com)"
Write-Host "  Dokploy   http://localhost:3000"
Write-Host "  Kestra    http://localhost:8085"
Write-Host "  Netdata   http://localhost:19999"
Write-Host "  Registry  http://localhost:5000/v2/_catalog"
Write-Host "  App       http://localhost:8000/health"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Open http://localhost:3100 and click Run client demo"
Write-Host "  2. Import flow: kestra/flows/dagger-dokploy-pipeline.yaml (if not done)"
Write-Host "  3. OKE + enlightlab.com ingress: oke/terraform/README.md"
Write-Host "  4. Meeting script: docs/manager-meeting-script.md"
Write-Host ""
Write-Host "Stop everything:  .\scripts\stop-platform.ps1"
Write-Host ""

Write-Step "Related containers"
$pattern = 'dokploy|kestra|netdata|registry|enlight-console'
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | Select-String -Pattern $pattern
