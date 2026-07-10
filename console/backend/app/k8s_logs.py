"""Read Kubernetes Job logs for pipeline executions (in-cluster)."""

from __future__ import annotations

import logging

logger = logging.getLogger(__name__)

_k8s_ready = False
_batch_api = None
_core_api = None


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


def get_job_logs(namespace: str, execution_id: str, tail: int = 80) -> dict:
    """Return job status + pod logs for a pipeline execution."""
    if not _init_k8s():
        return {"ok": False, "error": "Kubernetes API not available from console pod"}

    from kubernetes.client.rest import ApiException

    job_name = job_name_for_execution(execution_id)
    try:
        job = _batch_api.read_namespaced_job_status(job_name, namespace)
    except ApiException as exc:
        if exc.status == 404:
            return {"ok": False, "job": job_name, "status": "pending", "logs": ""}
        return {"ok": False, "error": str(exc)}

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
    try:
        pods = _core_api.list_namespaced_pod(
            namespace,
            label_selector=f"job-name={job_name}",
        )
        if pods.items:
            pod_name = pods.items[0].metadata.name
            logs = _core_api.read_namespaced_pod_log(
                pod_name,
                namespace,
                tail_lines=tail,
            )
    except ApiException as exc:
        logs = f"(logs not ready: {exc.reason})"

    return {
        "ok": True,
        "job": job_name,
        "status": phase,
        "logs": logs,
        "image": _job_container_image(job),
    }


def _job_container_image(job) -> str:
    try:
        return job.spec.template.spec.containers[0].image
    except (AttributeError, IndexError):
        return ""
