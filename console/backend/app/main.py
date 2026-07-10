from __future__ import annotations

import time
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .branding import DOMAIN_BASE, INGRESS_ROUTES
from .config import settings
from .kestra_client import (
    flow_exists,
    get_execution,
    get_execution_logs,
    parse_execution_summary,
    summary_from_kestra_lines,
    get_flow,
    make_client,
    parse_flow_meta,
    trigger_execution,
)
from .k8s_demo import ensure_argocd_app, get_demo_state, reset_demo_app
from .k8s_logs import get_job_logs, job_name_for_execution

app = FastAPI(title=settings.app_name, version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

PIPELINE_IMAGE_V9 = "ap-mumbai-1.ocir.io/bmitpaosivqx/enlight-pipeline:v9"
K8S_DEMO_NAMESPACE = "enlight-platform"
FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend" / "dist"


def _execution_error(data: dict[str, Any]) -> str | None:
    """Extract a client-friendly error from a failed Kestra execution."""
    for tr in data.get("taskRunList") or []:
        tstate = (tr.get("state") or {}).get("current")
        if tstate in ("FAILED", "KILLED"):
            tid = tr.get("taskId", "task")
            msg = (tr.get("state") or {}).get("message") or ""
            if msg:
                return f"{tid}: {msg[:300]}"
            return f"Task '{tid}' failed"
    top = (data.get("state") or {}).get("message")
    return str(top)[:300] if top else None


class DeployRequest(BaseModel):
    git_branch: str = "main"
    flow_id: str | None = Field(default=None, description="Override Kestra flow id")


def kestra_client(timeout: float = 30.0) -> httpx.AsyncClient:
    return make_client(
        timeout=timeout,
        username=settings.kestra_username or None,
        password=settings.kestra_password or None,
    )


async def probe_registry(url: str) -> dict[str, Any]:
    result = await probe(url, "/v2/")
    if not result.get("ok") and result.get("status_code") in (401, 403):
        result["ok"] = True
        result["note"] = "Registry reachable"
    return result


async def probe_kestra(url: str) -> dict[str, Any]:
    for path in ("/ui/", "/ui", "/api/v1/configs", "/api/v1/main/flows", "/"):
        result = await probe(url, path)
        if result.get("ok") or result.get("status_code") in (401, 403):
            # 401 means Kestra is up but needs auth — treat as healthy
            result["ok"] = True
            if result.get("status_code") in (401, 403):
                result["note"] = "Kestra up (auth required)"
            return result
    result = await probe(url, "/")
    if result.get("status_code") and result["status_code"] < 500:
        result["ok"] = True
        result["note"] = "Kestra server responding"
    return result


async def probe_gitops() -> dict[str, Any]:
    public = await probe(settings.gitops_url)
    if public.get("ok"):
        return public
    internal = await probe("http://argocd-server.argocd.svc.cluster.local", "/")
    if internal.get("ok"):
        internal["note"] = "ArgoCD reachable in cluster"
        internal["url"] = settings.gitops_url
    return internal


async def probe_metrics() -> dict[str, Any]:
    public = await probe(settings.hosts["metrics"])
    if public.get("ok"):
        return public
    internal = await probe(
        "http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local",
        "/login",
    )
    if internal.get("ok"):
        internal["note"] = "Grafana reachable in cluster"
        internal["url"] = settings.hosts["metrics"]
    return internal


async def probe(url: str, path: str = "", timeout: float = 4.0) -> dict[str, Any]:
    target = f"{url.rstrip('/')}{path}"
    started = time.perf_counter()
    try:
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
            response = await client.get(target)
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            return {
                "url": target,
                "ok": 200 <= response.status_code < 400,
                "status_code": response.status_code,
                "latency_ms": elapsed_ms,
            }
    except Exception as exc:  # noqa: BLE001
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        return {"url": target, "ok": False, "error": str(exc), "latency_ms": elapsed_ms}


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {
        "status": "ok",
        "service": settings.app_name,
        "mode": settings.mode,
        "console_version": "v28",
    }


@app.get("/api/info")
async def platform_info() -> dict[str, Any]:
    flow_ready = bool(settings.kestra_username and settings.kestra_password)
    try:
        async with kestra_client(timeout=8.0) as client:
            found = await flow_exists(
                client,
                settings.kestra_url,
                settings.kestra_namespace,
                settings.kestra_flow_id,
            )
            if found:
                flow_ready = True
            elif settings.mode == "oke" and settings.kestra_username:
                # Auth configured — assume flow exists if Kestra answers at all
                kestra_up = await client.get(f"{settings.kestra_url.rstrip('/')}/api/v1/configs")
                flow_ready = kestra_up.status_code < 500
    except Exception:  # noqa: BLE001
        flow_ready = bool(settings.mode == "oke" and settings.kestra_username)

    return {
        "mode": settings.mode,
        "flow_id": settings.kestra_flow_id,
        "flow_namespace": settings.kestra_namespace,
        "flow_ready": flow_ready,
        "flow_description": settings.flow_description,
        "flow_url": settings.kestra_flow_url(),
        "pipeline_image": settings.pipeline_image if settings.mode == "oke" else None,
        "build_engine": settings.build_engine,
        "expected_pipeline_image": PIPELINE_IMAGE_V9,
        "public_base_url": settings.public_base_url,
        "kestra_ui": settings.kestra_ui_base,
        "kestra_auth_configured": bool(settings.kestra_username and settings.kestra_password),
    }


@app.get("/api/status")
async def platform_status() -> dict[str, Any]:
    app_probe = await probe(f"{settings.app_public_url.rstrip('/')}", "/health")
    services: dict[str, Any] = {
        "console": await probe("http://127.0.0.1:3100", "/api/health"),
        "application": app_probe,
        "registry": await probe_registry(settings.registry_url),
    }
    if settings.mode == "oke":
        services["kestra"] = await probe_kestra(
            "http://kestra.enlight-platform.svc.cluster.local:8080"
        )
        services["gitops"] = await probe_gitops()
        services["netdata"] = await probe_metrics()
    else:
        services["kestra"] = await probe(settings.kestra_url, "/")
        services["gitops"] = await probe(settings.dokploy_url, "/")
        services["netdata"] = await probe(settings.netdata_url, "/api/v1/info")

    active = [s for s in services.values() if not s.get("skipped")]
    healthy = sum(1 for s in active if s.get("ok"))
    info = await platform_info()
    demo_state = get_demo_state() if settings.mode == "oke" else {}
    return {
        "mode": settings.mode,
        "healthy_count": healthy,
        "total": len(active),
        "all_healthy": healthy == len(active) and len(active) > 0,
        "services": services,
        "pipeline": info,
        "links": {
            "kestra": (
                f"{settings.kestra_ui_base}/ui"
                if settings.mode == "oke"
                else settings.kestra_url
            ),
            "gitops": settings.gitops_url if settings.mode == "oke" else settings.dokploy_url,
            "registry": settings.registry_url,
            "netdata": settings.hosts["metrics"] if settings.mode == "oke" else settings.netdata_url,
            "application": settings.app_public_url,
            "github": settings.github_repo,
        },
        "service_labels": {
            "console": "Platform console",
            "application": "Demo application",
            "registry": "Container registry",
            "kestra": "Pipeline automation",
            "gitops": "GitOps (ArgoCD)",
            "netdata": "Monitoring (Grafana)",
        }
        if settings.mode == "oke"
        else {
            "console": "Platform console",
            "application": "Demo application",
            "registry": "Image registry",
            "kestra": "Kestra",
            "gitops": "Dokploy",
            "netdata": "Netdata",
        },
        "ingress_preview": INGRESS_ROUTES,
        "paths": settings.hosts,
        "demo": {
            "proves": settings.demo_proves,
            "app_url": settings.app_public_url,
            "health_url": f"{settings.app_public_url.rstrip('/')}/health",
            "deploy_target": settings.deploy_target,
            "uses_dagger": settings.uses_dagger,
            "build_engine": settings.build_engine if settings.mode == "oke" else None,
            "build_note": (
                "Kaniko builds the image inside a Kubernetes Job, pushes to the registry, "
                "and ArgoCD deploys the GitOps manifest to the cluster."
                if settings.mode == "oke"
                and settings.kestra_flow_id == "oke-dagger-gitops-pipeline"
                else (
                    "Dagger builds the image inside the Kestra flow."
                    if settings.uses_dagger
                    else "Build runs via Dagger on your local machine."
                )
            ),
            **demo_state,
        },
        "app_note": (
            "Demo app at app."
            + (
                settings.public_base_url.replace("http://", "")
                .replace("https://", "")
                .split("/")[0]
                if settings.public_base_url
                else DOMAIN_BASE
            )
            if settings.mode == "oke"
            else None
        ),
    }


@app.post("/api/deploy")
async def trigger_deploy(body: DeployRequest | None = None) -> dict[str, Any]:
    req = body or DeployRequest()
    flow_id = req.flow_id or settings.kestra_flow_id
    namespace = settings.kestra_namespace

    if settings.mode == "oke" and not (settings.kestra_username and settings.kestra_password):
        raise HTTPException(
            status_code=401,
            detail={
                "message": "Kestra API requires Basic Auth",
                "hint": (
                    "Set KESTRA_USERNAME and KESTRA_PASSWORD on enlight-console "
                    "(same credentials you use to log into Kestra UI)."
                ),
            },
        )

    inputs: dict[str, str] = {
        "git_branch": req.git_branch,
        "app_health_url": settings.app_health_url,
    }
    if settings.mode == "oke":
        inputs["k8s_namespace"] = "enlight-platform"
        inputs["k8s_deployment"] = "fastapi-minimal"
        if flow_id == "oke-dagger-gitops-pipeline":
            from datetime import datetime, timezone

            ensure = ensure_argocd_app(settings.github_repo)
            if not ensure.get("ok"):
                raise HTTPException(
                    status_code=502,
                    detail={
                        "message": "Could not register ArgoCD app before deploy",
                        "hint": "Apply oke/manifests/32-console-rbac.yaml and retry.",
                        **ensure,
                    },
                )

            inputs["git_repo"] = settings.github_repo
            inputs["gitops_manifest"] = "oke/gitops/apps/fastapi/deployment.yaml"
            inputs["ocir_registry"] = "ap-mumbai-1.ocir.io/bmitpaosivqx"
            inputs["ocir_image_name"] = "enlight-fastapi"
            inputs["pipeline_image"] = settings.pipeline_image or PIPELINE_IMAGE_V9
            inputs["image_tag"] = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")

    try:
        async with kestra_client(timeout=30.0) as client:
            response = await trigger_execution(
                client,
                settings.kestra_url,
                namespace,
                flow_id,
                inputs,
            )
            if response.status_code >= 400:
                exists = await flow_exists(client, settings.kestra_url, namespace, flow_id)
                hint = (
                    "Wrong KESTRA_USERNAME / KESTRA_PASSWORD — use the same login as Kestra UI."
                    if response.status_code == 401
                    else (
                        f"Open flow '{flow_id}' in Kestra and click Execute. "
                        "If UI works but API fails, check auth env on console."
                    )
                )
                raise HTTPException(
                    status_code=response.status_code,
                    detail={
                        "message": "Could not start Kestra execution",
                        "flow_id": flow_id,
                        "flow_found": exists,
                        "body": response.text[:500],
                        "hint": hint,
                    },
                )
            data = response.json()
            execution_id = data.get("id")
            job_name = job_name_for_execution(str(execution_id))
            return {
                "triggered": True,
                "execution_id": execution_id,
                "flow_id": flow_id,
                "state": data.get("state", {}).get("current"),
                "url": settings.kestra_execution_url(str(execution_id), flow_id),
                "pipeline_image": inputs.get("pipeline_image"),
                "job_name": job_name,
                "run_page": f"/run?id={execution_id}",
            }
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail={
                "message": str(exc),
                "hint": "Ensure Kestra is running and console has KESTRA_USERNAME/PASSWORD.",
            },
        ) from exc


@app.post("/api/demo/reset")
async def reset_demo() -> dict[str, Any]:
    """Remove demo app from ArgoCD + cluster for a clean pipeline redeploy."""
    if settings.mode != "oke":
        raise HTTPException(status_code=404, detail="Demo reset only available in OKE mode")
    result = reset_demo_app(settings.github_repo)
    if not result.get("ok"):
        raise HTTPException(status_code=502, detail=result)
    return result


@app.get("/api/executions/{execution_id}")
async def execution_status(execution_id: str) -> dict[str, Any]:
    if settings.mode != "oke" or not (settings.kestra_username and settings.kestra_password):
        raise HTTPException(status_code=404, detail="Execution status only available in OKE mode")
    try:
        async with kestra_client(timeout=15.0) as client:
            data = await get_execution(
                client,
                settings.kestra_url,
                settings.kestra_namespace,
                execution_id,
            )
            if not data:
                raise HTTPException(status_code=404, detail="Execution not found")
            summary = parse_execution_summary(data)
            return {
                "execution_id": execution_id,
                "flow_id": summary.get("flow_id") or data.get("flowId"),
                "state": summary["state"],
                "url": settings.kestra_execution_url(execution_id, data.get("flowId")),
                "error": _execution_error(data),
                "tasks": summary["tasks"],
            }
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.get("/api/flow/meta")
async def flow_meta() -> dict[str, Any]:
    """Return live Kestra flow config — detect stale PT15M / old pipeline image."""
    if settings.mode != "oke":
        return {"ok": False}
    try:
        async with kestra_client(timeout=12.0) as client:
            flow = await get_flow(
                client,
                settings.kestra_url,
                settings.kestra_namespace,
                settings.kestra_flow_id,
            )
            meta = parse_flow_meta(flow)
            stale = (
                meta.get("wait_duration") in ("PT15M", "PT8M", "PT3M")
                or meta.get("has_rollout_restart")
                or meta.get("has_health_before")
                or (
                    meta.get("pipeline_image_default")
                    and "v9" not in str(meta.get("pipeline_image_default"))
                )
            )
            return {
                "ok": bool(flow),
                "flow_id": settings.kestra_flow_id,
                "stale": stale,
                "expected_wait": "PT90S",
                "expected_pipeline_image": PIPELINE_IMAGE_V9,
                **meta,
            }
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": str(exc)}


@app.get("/api/executions/{execution_id}/logs")
async def execution_logs(execution_id: str) -> dict[str, Any]:
    if settings.mode != "oke":
        raise HTTPException(status_code=404, detail="OKE mode only")

    kestra_lines: list[dict[str, Any]] = []
    kestra_error: str | None = None
    execution_summary: dict[str, Any] = {"state": None, "tasks": [], "flow_id": None}
    if settings.kestra_username and settings.kestra_password:
        try:
            async with kestra_client(timeout=15.0) as client:
                raw = await get_execution(
                    client,
                    settings.kestra_url,
                    settings.kestra_namespace,
                    execution_id,
                )
                execution_summary = parse_execution_summary(raw)
                kestra_lines = await get_execution_logs(
                    client,
                    settings.kestra_url,
                    settings.kestra_namespace,
                    execution_id,
                )
                if not execution_summary.get("tasks") and kestra_lines:
                    from_lines = summary_from_kestra_lines(kestra_lines)
                    if from_lines.get("tasks"):
                        execution_summary = {
                            "state": from_lines.get("state") or execution_summary.get("state"),
                            "tasks": from_lines["tasks"],
                            "flow_id": execution_summary.get("flow_id"),
                        }
        except Exception as exc:  # noqa: BLE001
            kestra_error = str(exc)

    job = get_job_logs(K8S_DEMO_NAMESPACE, execution_id, tail=200)
    return {
        "execution_id": execution_id,
        "execution": execution_summary,
        "kestra": kestra_lines,
        "job": job,
        "kestra_error": kestra_error,
    }


if FRONTEND_DIR.exists():
    app.mount("/assets", StaticFiles(directory=FRONTEND_DIR / "assets"), name="assets")

    @app.get("/")
    async def spa() -> FileResponse:
        return FileResponse(FRONTEND_DIR / "index.html")

    @app.get("/{full_path:path}")
    async def spa_fallback(full_path: str) -> FileResponse:
        if full_path.startswith("api/"):
            raise HTTPException(status_code=404)
        candidate = FRONTEND_DIR / full_path
        if candidate.is_file():
            return FileResponse(candidate)
        return FileResponse(FRONTEND_DIR / "index.html")
