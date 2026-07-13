from __future__ import annotations

import os
import time
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse

APP_NAME = os.getenv("APP_NAME", "Enlight Lab Demo App")
PLATFORM = os.getenv("PLATFORM_NAME", "DevOps Local Stack")
ENV = os.getenv("APP_ENV", "staging")
VERSION = os.getenv("APP_VERSION", "1.1.0")
DEPLOYED_AT = os.getenv("DEPLOYED_AT", datetime.now(timezone.utc).isoformat())

_START_TIME = time.time()
_REQUEST_COUNT = 0

app = FastAPI(title="enlight-demo-app", version=VERSION)

TEMPLATE = (Path(__file__).parent / "demo.html").read_text(encoding="utf-8")


@app.middleware("http")
async def count_requests(request, call_next):
    global _REQUEST_COUNT  # noqa: PLW0603
    _REQUEST_COUNT += 1
    response = await call_next(request)
    response.headers["X-App-Version"] = VERSION
    return response


@app.get("/", response_class=HTMLResponse)
def root() -> HTMLResponse:
    html = (
        TEMPLATE.replace("{{APP_NAME}}", APP_NAME)
        .replace("{{PLATFORM}}", PLATFORM)
        .replace("{{ENV}}", ENV)
        .replace("{{VERSION}}", VERSION)
        .replace("{{DEPLOYED_AT}}", DEPLOYED_AT)
    )
    return HTMLResponse(content=html)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": APP_NAME, "env": ENV}


@app.get("/api/info")
def info() -> JSONResponse:
    return JSONResponse(
        {
            "app": APP_NAME,
            "platform": PLATFORM,
            "environment": ENV,
            "version": VERSION,
            "status": "running",
            "deployed_at": DEPLOYED_AT,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "links": {
                "console": os.getenv("CONSOLE_URL", "http://144-24-100-85.nip.io"),
                "kestra": os.getenv("KESTRA_URL", "http://kestra.144-24-100-85.nip.io"),
                "gitops": os.getenv("GITOPS_URL", "https://argocd.enlightlab.com"),
            },
        }
    )


@app.get("/api/stats")
def stats() -> JSONResponse:
    uptime_s = int(time.time() - _START_TIME)
    return JSONResponse(
        {
            "uptime_seconds": uptime_s,
            "uptime_human": f"{uptime_s // 3600}h {(uptime_s % 3600) // 60}m {uptime_s % 60}s",
            "requests_served": _REQUEST_COUNT,
            "version": VERSION,
            "environment": ENV,
            "deployed_at": DEPLOYED_AT,
            "features": ["health", "info", "stats", "deploy-info"],
        }
    )


@app.get("/api/deploy-info")
def deploy_info() -> JSONResponse:
    return JSONResponse(
        {
            "pipeline": "oke-dagger-gitops-pipeline",
            "build_engine": "BuildKit",
            "gitops": "ArgoCD",
            "orchestrator": "Kestra",
            "registry": "OCIR",
            "namespace": "enlight-platform",
            "deployed_at": DEPLOYED_AT,
            "version": VERSION,
        }
    )
