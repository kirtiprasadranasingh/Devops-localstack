# Dokploy setup — FastAPI minimal

## Create service

1. Project: `fastapi-poc` (or your name)
2. **+ Create Service** → **Application**
3. Source: GitHub
4. Repository: `https://github.com/kirtiprasad2003/fastapi-minimal-poc`
5. Branch: `main`
6. Build context: `.`
7. Dockerfile: `Dockerfile`

## Runtime

| Setting | Value |
|---------|--------|
| Port | `8000` |
| **Host port publish** | `8000` → container `8000` (required for Kestra health check) |
| Health path | `/health` |

Kestra health URL (from inside Docker): `http://host.docker.internal:8000/health`  
Browser on Windows (use this for demo): `http://localhost:8000/health`  

Do **not** open `host.docker.internal` in Chrome/Edge on Windows — that hostname is for containers only.

No extra env vars needed for the minimal app.

## After deploy

- Logs should show Uvicorn on port `8000`
- `GET /health` → `{"status":"ok"}`

## Copy deploy webhook for Kestra

In the Application settings, copy the **Deploy webhook URL** for flow `minimal-deploy`.
