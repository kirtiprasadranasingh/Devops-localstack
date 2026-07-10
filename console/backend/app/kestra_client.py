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
    """Fetch execution log lines from Kestra (client-friendly, no raw JSON blobs)."""
    base = base_url.rstrip("/")
    lines: list[dict[str, Any]] = []

    execution = await get_execution(client, base_url, namespace, execution_id)
    flow_id = (execution or {}).get("flowId") or ""

    if execution:
        state = execution.get("state") or {}
        current = state.get("current") if isinstance(state, dict) else state
        lines.append({"level": "INFO", "message": f"Execution state: {current}"})
        for tr in execution.get("taskRunList") or []:
            tid = tr.get("taskId") or tr.get("id") or "?"
            tstate = tr.get("state") or {}
            current_state = tstate.get("current") if isinstance(tstate, dict) else tstate
            dur = tr.get("duration", "")
            lines.append(
                {
                    "level": "INFO",
                    "message": f"Task {tid}: {current_state} {dur}".strip(),
                }
            )

    log_paths = [
        f"/api/v1/main/executions/{namespace}/{execution_id}/logs/download",
        f"/api/v1/main/executions/{namespace}/{execution_id}/logs",
    ]
    if flow_id:
        log_paths.extend(
            [
                f"/api/v1/main/logs/{namespace}/{flow_id}/{execution_id}",
                f"/api/v1/logs/{namespace}/{flow_id}/{execution_id}",
            ]
        )
    log_paths.append(f"/api/v1/logs/{execution_id}")

    for path in log_paths:
        try:
            response = await client.get(f"{base}{path}")
            if response.status_code != 200 or not response.text.strip():
                continue
            got = 0
            for raw in response.text.splitlines()[-80:]:
                raw = raw.strip()
                if not raw or raw in ("[]", "{}", "null"):
                    continue
                human = _humanize_kestra_log_line(raw)
                if human and human not in ("[]", "{}"):
                    lines.append({"level": "INFO", "message": human})
                    got += 1
            if got:
                break
        except Exception:  # noqa: BLE001
            continue

    return lines


def _humanize_kestra_log_line(raw: str) -> str | None:
    """Convert Kestra JSON log line to short client text."""
    raw = raw.strip()
    if not raw or raw in ("[]", "{}", "null"):
        return None
    if raw.startswith("{"):
        try:
            import json

            j = json.loads(raw)
            msg = j.get("message") or ""
            tid = j.get("taskId") or ""
            if "Deploy complete" in msg:
                return "Deployment complete"
            if "response code '200'" in msg or 'response code "200"' in msg:
                return "Health check passed"
            if j.get("level") == "ERROR" and msg:
                short = msg.split("\n")[0][:140]
                return f"Error ({tid}): {short}" if tid else f"Error: {short}"
            if msg and len(msg) < 160 and not msg.startswith("{"):
                return msg
            if msg and any(
                k in msg
                for k in (
                    "Clone",
                    "Kaniko",
                    "GitOps",
                    "deploy:",
                    "DONE",
                    "Deploy complete",
                    "health",
                )
            ):
                return msg.split("\n")[0][:160]
            return None
        except Exception:  # noqa: BLE001
            return None
    if len(raw) > 200:
        return None
    return raw


async def get_execution(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    execution_id: str,
) -> dict[str, Any] | None:
    base = base_url.rstrip("/")
    for eid in dict.fromkeys([execution_id, execution_id.lower(), execution_id.upper()]):
        for path in (
            f"/api/v1/main/executions/{namespace}/{eid}",
            f"/api/v1/executions/{namespace}/{eid}",
        ):
            try:
                response = await client.get(f"{base}{path}")
                if response.status_code == 200:
                    return response.json()
            except Exception:  # noqa: BLE001
                continue
    return None


def parse_execution_summary(data: dict[str, Any] | None) -> dict[str, Any]:
    """Normalize Kestra execution JSON into state + task list for the console UI."""
    if not data:
        return {"state": None, "tasks": [], "flow_id": None}

    state = data.get("state") or {}
    current = state.get("current") if isinstance(state, dict) else state
    tasks: list[dict[str, Any]] = []
    for tr in data.get("taskRunList") or data.get("taskRuns") or []:
        tid = tr.get("taskId") or tr.get("id")
        if not tid:
            continue
        tstate = tr.get("state") or {}
        current_state = tstate.get("current") if isinstance(tstate, dict) else tstate
        tasks.append(
            {
                "id": tid,
                "state": current_state,
                "duration": tr.get("duration"),
            }
        )

    if not current or current == "RUNNING":
        tracked = [t for t in tasks if t.get("state")]
        if tracked and all(t.get("state") == "SUCCESS" for t in tracked):
            current = "SUCCESS"
        elif any(t.get("state") in ("FAILED", "KILLED") for t in tasks):
            current = "FAILED"
    if any(t.get("id") == "done" and t.get("state") == "SUCCESS" for t in tasks):
        current = "SUCCESS"

    return {
        "state": current,
        "tasks": tasks,
        "flow_id": data.get("flowId"),
    }


def summary_from_kestra_lines(lines: list[dict[str, Any]]) -> dict[str, Any]:
    """Build execution summary from Task / Execution state log lines."""
    import re

    tasks: list[dict[str, Any]] = []
    state: str | None = None
    seen: set[str] = set()
    for line in lines:
        msg = (line.get("message") if isinstance(line, dict) else str(line)) or ""
        if msg.startswith("Execution state:"):
            state = msg.split(":", 1)[1].strip()
            continue
        match = re.match(r"^Task ([^:]+):\s*(\S+)", msg)
        if not match:
            continue
        tid, tstate = match.group(1), match.group(2)
        if tid in seen:
            continue
        seen.add(tid)
        tasks.append({"id": tid, "state": tstate})
    if state is None and tasks and all(t.get("state") == "SUCCESS" for t in tasks):
        state = "SUCCESS"
    return {"state": state, "tasks": tasks, "flow_id": None}


def compute_pipeline_ui(execution_summary: dict[str, Any], job: dict[str, Any], logs: str) -> dict[str, Any]:
    """Server-side phase state — Kestra tasks when available, else K8s build job status."""
    import re

    tasks = execution_summary.get("tasks") or []
    task_map = {t["id"]: t["state"] for t in tasks if t.get("id")}
    ex_state = execution_summary.get("state")
    build_done = job.get("status") == "complete" and bool(
        re.search(r"DONE ap-mumbai", logs or "")
    )

    if ex_state == "SUCCESS" or task_map.get("done") == "SUCCESS":
        return {"state": "SUCCESS", "pct": 100, "tasks": tasks}

    if task_map.get("health-after") == "SUCCESS":
        return {"state": "RUNNING", "pct": 92, "tasks": tasks}

    if task_map.get("wait-pipeline") == "SUCCESS":
        return {"state": "RUNNING", "pct": 78, "tasks": tasks}

    if build_done or task_map.get("run-pipeline-job") == "SUCCESS":
        return {"state": "RUNNING", "pct": 65, "tasks": tasks}

    return {"state": ex_state or "RUNNING", "pct": 40, "tasks": tasks}


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
