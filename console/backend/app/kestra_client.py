from __future__ import annotations

from typing import Any

import httpx


def auth_tuple(username: str | None, password: str | None) -> tuple[str, str] | None:
    if username and password:
        return (username, password)
    return None


async def flow_exists(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    flow_id: str,
) -> bool:
    """Best-effort check — Kestra versions differ."""
    base = base_url.rstrip("/")
    candidates = [
        f"{base}/api/v1/main/flows/{namespace}/{flow_id}",
        f"{base}/api/v1/flows/{namespace}/{flow_id}",
        f"{base}/api/v1/main/flows/search?q={flow_id}&size=20",
        f"{base}/api/v1/flows/search?q={flow_id}&size=20",
    ]
    for url in candidates:
        try:
            response = await client.get(url)
            if response.status_code != 200:
                continue
            if "/search" in url:
                text = response.text
                if flow_id in text and namespace in text:
                    return True
                continue
            return True
        except Exception:  # noqa: BLE001
            continue
    return False


async def get_flow(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    flow_id: str,
) -> dict[str, Any] | None:
    base = base_url.rstrip("/")
    for path in (
        f"/api/v1/main/flows/{namespace}/{flow_id}",
        f"/api/v1/flows/{namespace}/{flow_id}",
    ):
        try:
            response = await client.get(f"{base}{path}")
            if response.status_code == 200:
                return response.json()
        except Exception:  # noqa: BLE001
            continue
    return None


def parse_flow_meta(flow: dict[str, Any] | None) -> dict[str, Any]:
    """Extract pipeline_image default and wait duration from flow JSON."""
    meta: dict[str, Any] = {
        "pipeline_image_default": None,
        "wait_duration": None,
        "has_rollout_restart": False,
        "has_health_before": False,
        "flow_revision": flow.get("revision") if flow else None,
    }
    if not flow:
        return meta

    for inp in flow.get("inputs") or []:
        if inp.get("id") == "pipeline_image":
            meta["pipeline_image_default"] = inp.get("defaults")

    for task in flow.get("tasks") or []:
        tid = task.get("id")
        if tid == "wait-pipeline":
            meta["wait_duration"] = task.get("duration")
        if tid == "health-before":
            meta["has_health_before"] = True
        if tid == "rollout-status":
            meta["has_rollout_restart"] = True

    return meta


async def get_execution_logs(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    execution_id: str,
) -> list[dict[str, Any]]:
    """Fetch execution log lines from Kestra."""
    base = base_url.rstrip("/")
    lines: list[dict[str, Any]] = []

    execution = await get_execution(client, base_url, namespace, execution_id)
    if execution:
        for tr in execution.get("taskRunList") or []:
            for log in tr.get("outputs") or {}:
                pass
        state = (execution.get("state") or {}).get("current")
        lines.append({"level": "INFO", "message": f"Execution state: {state}"})
        for tr in execution.get("taskRunList") or []:
            tid = tr.get("taskId", "?")
            tstate = (tr.get("state") or {}).get("current", "?")
            dur = tr.get("duration", "")
            lines.append({"level": "INFO", "message": f"Task {tid}: {tstate} {dur}"})

    for path in (
        f"/api/v1/main/executions/{namespace}/{execution_id}/logs/download",
        f"/api/v1/logs/{execution_id}",
    ):
        try:
            response = await client.get(f"{base}{path}")
            if response.status_code == 200 and response.text.strip():
                for raw in response.text.splitlines()[-40:]:
                    lines.append({"level": "INFO", "message": raw})
                break
        except Exception:  # noqa: BLE001
            continue

    return lines


async def get_execution(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    execution_id: str,
) -> dict[str, Any] | None:
    base = base_url.rstrip("/")
    for path in (
        f"/api/v1/main/executions/{namespace}/{execution_id}",
        f"/api/v1/executions/{namespace}/{execution_id}",
    ):
        try:
            response = await client.get(f"{base}{path}")
            if response.status_code == 200:
                return response.json()
        except Exception:  # noqa: BLE001
            continue
    return None


async def trigger_execution(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    flow_id: str,
    inputs: dict[str, str] | None = None,
) -> httpx.Response:
    """Start a Kestra execution (multipart first — required by Kestra OSS)."""
    base = base_url.rstrip("/")
    payload = {k: v for k, v in (inputs or {}).items() if v}
    main_exec = f"{base}/api/v1/main/executions/{namespace}/{flow_id}"
    legacy_exec = f"{base}/api/v1/executions/{namespace}/{flow_id}"

    # Kestra OSS: each input is a separate multipart field named after the input id.
    multipart_files = [(key, (None, value)) for key, value in payload.items()]
    prefixed_files = [(f"inputs.{key}", (None, value)) for key, value in payload.items()]
    form_data = payload

    attempts: list[tuple[str, dict[str, Any]]] = [
        (main_exec, {"files": multipart_files} if multipart_files else {}),
        (main_exec, {"files": prefixed_files} if prefixed_files else {}),
        (main_exec, {"data": form_data} if form_data else {}),
        (main_exec, {}),
        (legacy_exec, {"json": {"inputs": payload}}),
        (legacy_exec, {}),
    ]

    last_response: httpx.Response | None = None
    for url, kwargs in attempts:
        response = await client.post(url, **kwargs)
        last_response = response
        if response.status_code < 400:
            return response

    assert last_response is not None
    return last_response


def make_client(
    timeout: float = 30.0,
    username: str | None = None,
    password: str | None = None,
) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        timeout=timeout,
        auth=auth_tuple(username, password),
        follow_redirects=True,
    )
