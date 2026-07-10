"""Read Kubernetes Job logs for pipeline executions (in-cluster)."""

from __future__ import annotations

import ast
import logging
import re

logger = logging.getLogger(__name__)

_k8s_ready = False
_batch_api = None
_core_api = None

PIPELINE_CONTAINER = "pipeline"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _normalize_log_text(raw: object) -> str:
    """Ensure pod log text is a real UTF-8 string with newlines (not bytes repr)."""
    if raw is None:
        return ""
    if isinstance(raw, bytes):
        text = raw.decode("utf-8", errors="replace")
    else:
        text = str(raw)
        if len(text) >= 3 and text[0] == "b" and text[1] in ("'", '"'):
            try:
                evaluated = ast.literal_eval(text)
                if isinstance(evaluated, bytes):
                    text = evaluated.decode("utf-8", errors="replace")
            except (SyntaxError, ValueError):
                pass
    text = _ANSI.sub("", text)
    return text.replace("\\n", "\n") if "\\n" in text and "\n" not in text else text


def _init_k8s() -> bool:
    global _k8s_ready, _batch_api, _core_api
    if _batch_api is not None:
        return _k8s_ready
    try:
        from kubernetes import client, config

        config.load_incluster_config()
        _batch_api = client.BatchV1Api()
        _core_api = client.CoreV1Api()
        _k8s_ready = True
    except Exception as exc:  # noqa: BLE001
        logger.warning("Kubernetes in-cluster config unavailable: %s", exc)
        _k8s_ready = False
    return _k8s_ready


def job_name_for_execution(execution_id: str) -> str:
    return f"enlight-pipeline-{execution_id.lower()}"


def _job_phase(job) -> str:
    conditions = job.status.conditions or []
    if any(c.type == "Complete" and c.status == "True" for c in conditions):
        return "complete"
    if any(c.type == "Failed" and c.status == "True" for c in conditions):
        return "failed"
    if job.status.active:
        return "running"
    if job.status.succeeded:
        return "complete"
    if job.status.failed:
        return "failed"
    return "running"


def _read_pod_logs(namespace: str, pod_name: str, tail: int) -> str:
    from kubernetes.client.rest import ApiException

    for kwargs in (
        {"tail_lines": tail, "container": PIPELINE_CONTAINER},
        {"tail_lines": tail},
    ):
        try:
            raw = _core_api.read_namespaced_pod_log(pod_name, namespace, **kwargs)
            return _normalize_log_text(raw)
        except ApiException as exc:
            if exc.status == 400 and "container" in kwargs:
                continue
            raise
    return ""


def _collect_pod_logs(namespace: str, job_name: str, tail: int) -> tuple[str, str | None, str]:
    """Return (logs, error_hint, inferred_phase)."""
    from kubernetes.client.rest import ApiException

    try:
        pods = _core_api.list_namespaced_pod(
            namespace,
            label_selector=f"job-name={job_name}",
        )
    except ApiException as exc:
        return "", f"Cannot list pods for {job_name}: {exc.reason}", "pending"

    if not pods.items:
        return "", None, "pending"

    ranked = sorted(
        pods.items,
        key=lambda p: (
            0 if (p.status.phase or "") in ("Running", "Succeeded") else 1,
            p.metadata.creation_timestamp or "",
        ),
    )

    inferred = "pending"
    for pod in ranked:
        pod_phase = pod.status.phase or ""
        if pod_phase == "Succeeded":
            inferred = "complete"
        elif pod_phase == "Running":
            inferred = "running"
        elif pod_phase == "Failed":
            inferred = "failed"

        pod_name = pod.metadata.name
        try:
            logs = _read_pod_logs(namespace, pod_name, tail)
            if logs:
                return logs, None, inferred
        except ApiException as exc:
            if exc.status == 404:
                continue
            return "", f"Logs not ready ({exc.reason})", inferred

    return "", "Build pod started — logs not ready yet…", inferred


def _job_container_image(job) -> str:
    try:
        return job.spec.template.spec.containers[0].image
    except (AttributeError, IndexError):
        return ""


def get_job_logs(namespace: str, execution_id: str, tail: int = 200) -> dict:
    """Return job status + pod logs for a pipeline execution."""
    job_name = job_name_for_execution(execution_id)
    if not _init_k8s():
        return {
            "ok": False,
            "job": job_name,
            "status": "unavailable",
            "logs": "",
            "error": "Kubernetes API not available from console pod",
        }

    from kubernetes.client.rest import ApiException

    job = None
    phase = "pending"
    job_error: str | None = None

    # Prefer read_namespaced_job (needs jobs/get, not jobs/status)
    try:
        job = _batch_api.read_namespaced_job(job_name, namespace)
        phase = _job_phase(job)
    except ApiException as exc:
        if exc.status == 404:
            logs, hint, pod_phase = _collect_pod_logs(namespace, job_name, tail)
            return {
                "ok": True,
                "job": job_name,
                "status": pod_phase if logs else "pending",
                "logs": logs,
                "hint": hint,
            }
        if exc.status == 403:
            job_error = (
                f"RBAC denied reading job {job_name} — apply oke/manifests/32-console-rbac.yaml "
                "and restart enlight-console"
            )
        else:
            job_error = f"Cannot read job {job_name}: {exc.reason}"

    logs, hint, pod_phase = _collect_pod_logs(namespace, job_name, tail)
    if phase == "pending" and pod_phase != "pending":
        phase = pod_phase

    if job_error and not logs:
        return {
            "ok": False,
            "job": job_name,
            "status": "error",
            "logs": "",
            "error": job_error,
            "hint": hint,
        }

    return {
        "ok": True,
        "job": job_name,
        "status": phase,
        "logs": logs,
        "hint": hint or job_error,
        "image": _job_container_image(job) if job else "",
    }
