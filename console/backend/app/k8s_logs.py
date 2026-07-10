"""Read Kubernetes Job logs for pipeline executions (in-cluster)."""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

_k8s_ready = False
_batch_api = None
_core_api = None

PIPELINE_CONTAINER = "pipeline"


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


def _read_pod_logs(namespace: str, pod_name: str, tail: int) -> str:
    from kubernetes.client.rest import ApiException

    for kwargs in (
        {"tail_lines": tail, "container": PIPELINE_CONTAINER},
        {"tail_lines": tail},
    ):
        try:
            return _core_api.read_namespaced_pod_log(pod_name, namespace, **kwargs)
        except ApiException as exc:
            if exc.status == 400 and "container" in kwargs:
                continue
            raise
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

    try:
        job = _batch_api.read_namespaced_job_status(job_name, namespace)
    except ApiException as exc:
        if exc.status == 404:
            return {
                "ok": True,
                "job": job_name,
                "status": "pending",
                "logs": "",
                "hint": "Waiting for pipeline job to start…",
            }
        return {
            "ok": False,
            "job": job_name,
            "status": "error",
            "logs": "",
            "error": f"Cannot read job {job_name}: {exc.reason}",
        }

    conditions = job.status.conditions or []
    complete = any(c.type == "Complete" and c.status == "True" for c in conditions)
    failed = any(c.type == "Failed" and c.status == "True" for c in conditions)
    if complete:
        phase = "complete"
    elif failed:
        phase = "failed"
    else:
        phase = "running"

    logs = ""
    log_error = None
    try:
        pods = _core_api.list_namespaced_pod(
            namespace,
            label_selector=f"job-name={job_name}",
        )
        # Prefer Running/Succeeded pods; newest last in list often = latest attempt
        ranked = sorted(
            pods.items,
            key=lambda p: (
                0 if (p.status.phase or "") in ("Running", "Succeeded") else 1,
                p.metadata.creation_timestamp or "",
            ),
        )
        for pod in ranked:
            pod_name = pod.metadata.name
            try:
                logs = _read_pod_logs(namespace, pod_name, tail)
                if logs:
                    break
            except ApiException as exc:
                log_error = f"Logs not ready ({exc.reason})"
                continue
    except ApiException as exc:
        log_error = f"Cannot list pods: {exc.reason}"

    return {
        "ok": True,
        "job": job_name,
        "status": phase,
        "logs": logs,
        "hint": log_error if not logs else None,
        "image": _job_container_image(job),
    }


def _job_container_image(job) -> str:
    try:
        return job.spec.template.spec.containers[0].image
    except (AttributeError, IndexError):
        return ""
