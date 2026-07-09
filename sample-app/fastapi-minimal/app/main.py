from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse

APP_NAME = os.getenv("APP_NAME", "Enlight Lab Demo App")
PLATFORM = os.getenv("PLATFORM_NAME", "DevOps Local Stack")
ENV = os.getenv("APP_ENV", "staging")
VERSION = os.getenv("APP_VERSION", "1.0.0")

app = FastAPI(title="enlight-demo-app", version=VERSION)

TEMPLATE = (Path(__file__).parent / "demo.html").read_text(encoding="utf-8")


@app.get("/", response_class=HTMLResponse)
def root() -> HTMLResponse:
    html = (
        TEMPLATE.replace("{{APP_NAME}}", APP_NAME)
        .replace("{{PLATFORM}}", PLATFORM)
        .replace("{{ENV}}", ENV)
        .replace("{{VERSION}}", VERSION)
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
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "links": {
                "console": os.getenv("CONSOLE_URL", "http://144-24-100-85.nip.io"),
                "kestra": os.getenv("KESTRA_URL", "http://kestra.144-24-100-85.nip.io"),
                "gitops": os.getenv("GITOPS_URL", "https://argocd.enlightlab.com"),
            },
        }
    )
