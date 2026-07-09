# Netdata setup for PoC

## Start

```powershell
cd D:\platform-poc\netdata
docker compose up -d
```

Or: `.\scripts\restart-netdata.ps1`

Open `http://localhost:19999`.

**Windows note:** Full host `/proc` and `/sys` mounts were removed — they often crash Netdata on Docker Desktop. You still get Docker container metrics and the dashboard.

First start can take **1-3 minutes**.

## Demo panels to show

- System CPU and memory
- Docker containers CPU and memory
- Network I/O during deployment window

## PoC validation

1. Keep Netdata dashboard open.
2. Trigger deployment from Kestra.
3. Show metric spike while deployment runs.
4. Show stable baseline after deployment completes.
