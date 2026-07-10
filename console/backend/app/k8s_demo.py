"""Reset / restore the fastapi-minimal demo app via ArgoCD (in-cluster)."""

from __future__ import annotations

import logging
import time
from typing import Any

logger = logging.getLogger(__name__)

DEMO_NAMESPACE = "enlight-platform"
DEMO_DEPLOYMENT = "fastapi-minimal"
ARGOCD_NAMESPACE = "argocd"
ARGOCD_APP = "fastapi-minimal"
GITOPS_PATH = "oke/gitops/apps/fastapi"
ARGO_GROUP = "argoproj.io"
ARGO_VERSION = "v1alpha1"
ARGO_PLURAL = "applications"

_custom_api = None
_apps_api = None
_k8s_ready = False


def _init_k8s() -> bool:
    global _custom_api, _apps_api, _k8s_ready
    if _custom_api is not None:
        return _k8s_ready
    try:
        from kubernetes import client, config

        config.load_incluster_config()
        _custom_api = client.CustomObjectsApi()
        _apps_api = client.AppsV1Api()
        _k8s_ready = True
    except Exception as exc:  # noqa: BLE001
        logger.warning("Kubernetes in-cluster config unavailable: %s", exc)
        _k8s_ready = False
    return _k8s_ready


def _repo_url(github_repo: str) -> str:
    url = github_repo.rstrip("/")
    return url if url.endswith(".git") else f"{url}.git"


def argocd_app_manifest(github_repo: str) -> dict[str, Any]:
    return {
        "apiVersion": f"{ARGO_GROUP}/v1alpha1",
        "kind": "Application",
        "metadata": {
            "name": ARGOCD_APP,
            "namespace": ARGOCD_NAMESPACE,
            "finalizers": ["resources-finalizer.argocd.argoproj.io"],
        },
        "spec": {
            "project": "default",
            "source": {
                "repoURL": _repo_url(github_repo),
                "targetRevision": "main",
                "path": GITOPS_PATH,
                "directory": {"recurse": False},
            },
            "destination": {
                "server": "https://kubernetes.default.svc",
                "namespace": DEMO_NAMESPACE,
            },
            "syncPolicy": {
                "automated": {"prune": True, "selfHeal": True},
                "syncOptions": ["CreateNamespace=false"],
            },
        },
    }


def _deployment_exists() -> bool:
    from kubernetes.client.rest import ApiException

    try:
        _apps_api.read_namespaced_deployment(DEMO_DEPLOYMENT, DEMO_NAMESPACE)
        return True
    except ApiException as exc:
        if exc.status == 404:
            return False
        raise


def _argocd_app_exists() -> bool:
    from kubernetes.client.rest import ApiException

    try:
        _custom_api.get_namespaced_custom_object(
            ARGO_GROUP,
            ARGO_VERSION,
            ARGOCD_NAMESPACE,
            ARGO_PLURAL,
            ARGOCD_APP,
        )
        return True
    except ApiException as exc:
        if exc.status == 404:
            return False
        raise


def get_demo_state() -> dict[str, Any]:
    if not _init_k8s():
        return {
            "argocd_app": None,
            "deployment_present": None,
            "demo_live": None,
            "reset_available": False,
            "k8s_api": False,
        }

    try:
        has_app = _argocd_app_exists()
        has_deploy = _deployment_exists()
        return {
            "argocd_app": has_app,
            "deployment_present": has_deploy,
            "demo_live": has_deploy,
            "reset_available": has_app or has_deploy,
            "k8s_api": True,
        }
    except Exception as exc:  # noqa: BLE001
        logger.exception("get_demo_state failed")
        return {
            "argocd_app": None,
            "deployment_present": None,
            "demo_live": None,
            "reset_available": False,
            "k8s_api": True,
            "error": str(exc),
        }


def reset_demo_app(github_repo: str) -> dict[str, Any]:
    """Remove ArgoCD app (cascade) so the demo workload is gone until pipeline redeploys."""
    if not _init_k8s():
        return {"ok": False, "error": "Kubernetes API not available from console pod"}

    from kubernetes import client
    from kubernetes.client.rest import ApiException

    state_before = get_demo_state()
    if not state_before.get("reset_available"):
        return {
            "ok": True,
            "already_reset": True,
            "message": "Demo app is already removed from the cluster.",
            **state_before,
        }

    try:
        if state_before.get("argocd_app"):
            _custom_api.delete_namespaced_custom_object(
                ARGO_GROUP,
                ARGO_VERSION,
                ARGOCD_NAMESPACE,
                ARGO_PLURAL,
                ARGOCD_APP,
                body=client.V1DeleteOptions(
                    propagation_policy="Foreground",
                    grace_period_seconds=0,
                ),
            )
        elif state_before.get("deployment_present"):
            _apps_api.delete_namespaced_deployment(
                DEMO_DEPLOYMENT,
                DEMO_NAMESPACE,
                body=client.V1DeleteOptions(grace_period_seconds=0),
            )
    except ApiException as exc:
        return {"ok": False, "error": f"Reset failed: {exc.reason}", "status": exc.status}

    for _ in range(12):
        time.sleep(2)
        state = get_demo_state()
        if not state.get("deployment_present") and not state.get("argocd_app"):
            return {
                "ok": True,
                "message": "Demo app removed. Run the pipeline to build with Kaniko and redeploy.",
                **state,
            }

    return {
        "ok": True,
        "message": "Reset requested — workload may take a few more seconds to disappear.",
        **get_demo_state(),
    }


def ensure_argocd_app(github_repo: str) -> dict[str, Any]:
    """Create ArgoCD Application if missing (needed after reset before GitOps sync)."""
    if not _init_k8s():
        return {"ok": False, "error": "Kubernetes API not available from console pod"}

    from kubernetes.client.rest import ApiException

    manifest = argocd_app_manifest(github_repo)
    try:
        if _argocd_app_exists():
            return {"ok": True, "created": False, "message": "ArgoCD app already registered"}
        _custom_api.create_namespaced_custom_object(
            ARGO_GROUP,
            ARGO_VERSION,
            ARGOCD_NAMESPACE,
            ARGO_PLURAL,
            manifest,
        )
        return {
            "ok": True,
            "created": True,
            "message": "ArgoCD app registered — pipeline will sync the new image.",
        }
    except ApiException as exc:
        if exc.status == 409:
            return {"ok": True, "created": False, "message": "ArgoCD app already exists"}
        return {"ok": False, "error": f"Could not register ArgoCD app: {exc.reason}"}
