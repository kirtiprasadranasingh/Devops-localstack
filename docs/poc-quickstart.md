# PoC Quickstart (with Dagger)

## Prerequisites

- Docker Desktop running
- Dokploy app created for `fastapi-minimal-poc`
- Tokens in `kestra/.env` (from `.env.example`)

## Start stack

```powershell
cd D:\platform-poc\registry && docker compose up -d
cd D:\platform-poc\dokploy && docker compose up -d
cd D:\platform-poc\kestra && docker compose up -d
cd D:\platform-poc\netdata && docker compose up -d
```

URLs:

- Dokploy: http://localhost:3000
- Kestra: http://localhost:8085
- Netdata: http://localhost:19999

## Run pipeline (manual)

1. Push a change to `fastapi-minimal-poc` on GitHub (optional).
2. Open Kestra → flow `dagger-dokploy-pipeline` → **Execute**.
3. Input: `app_health_url` = your app `/health` URL.
4. Watch logs: clone → Dagger build/push → Dokploy deploy → health OK.

## Verify Dagger locally (optional)

```powershell
cd D:\platform-poc\sample-app\fastapi-minimal\dagger
dagger call pipeline --registry=localhost:5000 --image=fastapi-minimal --tag=latest
```

(Add Dokploy flags when testing full deploy.)

## Manager demo

See `manager-demo-runbook.md`.
