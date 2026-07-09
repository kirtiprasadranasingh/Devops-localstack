# FastAPI Minimal PoC

Lightweight app for platform demo.

## Endpoints

- `GET /` — `{"message":"FastAPI PoC is running"}`
- `GET /health` — `{"status":"ok"}`

## Local run

```powershell
docker build -t fastapi-minimal .
docker run --rm -p 8000:8000 fastapi-minimal
```

## Dagger pipeline

```powershell
cd dagger
dagger call minimal-pipeline `
  --registry=localhost:5000 `
  --image=fastapi-minimal `
  --tag=latest `
  --dokploy-url=http://localhost:3000 `
  --dokploy-token=env:DOKPLOY_TOKEN `
  --application-id=YOUR_APP_ID
```

Functions:

- `build_and_publish` — build Dockerfile, push to registry
- `deploy_dokploy` — call Dokploy `application.deploy` API
- `pipeline` — both steps

## Push to GitHub

Repo: `https://github.com/kirtiprasad2003/fastapi-minimal-poc`  
Kestra clones this repo and runs `dagger/` on execute.
