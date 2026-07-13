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
                    "BuildKit",
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


def compute_pipeline_ui(
    execution_summary: dict[str, Any],
    job: dict[str, Any],
    logs: str,
    kestra_lines: list[dict[str, Any]] | None = None,
    live_health_ok: bool = False,
) -> dict[str, Any]:
    """Server-side phase state — Kestra tasks, log lines, K8s job, live app probe."""
    import re

    tasks: list[dict[str, Any]] = list(execution_summary.get("tasks") or [])
    task_map: dict[str, str] = {t["id"]: t["state"] for t in tasks if t.get("id")}

    for t in summary_from_kestra_lines(kestra_lines or []).get("tasks") or []:
        tid = t.get("id")
        if tid and tid not in task_map:
            task_map[tid] = t["state"]
            tasks.append(t)

    for line in kestra_lines or []:
        msg = (line.get("message") if isinstance(line, dict) else str(line)) or ""
        if "Execution state: SUCCESS" in msg:
            execution_summary["state"] = "SUCCESS"
        if "Health check passed" in msg or "response code '200'" in msg:
            task_map["health-after"] = "SUCCESS"
        if "Deployment complete" in msg or "Deploy complete" in msg:
            task_map["done"] = "SUCCESS"
            task_map["wait-pipeline"] = task_map.get("wait-pipeline") or "SUCCESS"
            task_map["health-after"] = task_map.get("health-after") or "SUCCESS"
            task_map["run-pipeline-job"] = task_map.get("run-pipeline-job") or "SUCCESS"

    build_done = job.get("status") == "complete" and bool(
        re.search(r"DONE ap-mumbai", logs or "")
    )
    git_pushed = bool(re.search(r"GitOps commit|deploy:.*\[kestra pipeline\]", logs or ""))

    if job.get("status") == "complete":
        task_map["run-pipeline-job"] = task_map.get("run-pipeline-job") or "SUCCESS"
    elif job.get("status") == "failed":
        task_map["run-pipeline-job"] = "FAILED"

    ex_state = execution_summary.get("state")
    wait = task_map.get("wait-pipeline")
    health = task_map.get("health-after")
    done = task_map.get("done")
    job_state = task_map.get("run-pipeline-job")

    tracked = [t for t in tasks if t.get("id") and t.get("state")]
    all_success = bool(tracked) and all(t.get("state") == "SUCCESS" for t in tracked)

    is_success = (
        ex_state == "SUCCESS"
        or done == "SUCCESS"
        or all_success
        or (health == "SUCCESS" and wait == "SUCCESS")
        or (health == "SUCCESS" and build_done and git_pushed)
        or (health == "SUCCESS" and build_done and wait == "SUCCESS")
        or (live_health_ok and build_done and git_pushed)
    )

    if is_success:
        phases = [
            {"id": "trigger", "status": "success"},
            {"id": "build", "status": "success"},
            {"id": "deploy", "status": "success"},
            {"id": "verify", "status": "success"},
        ]
        return {
            "state": "SUCCESS",
            "pct": 100,
            "tasks": tasks,
            "phases": phases,
            "live_health": live_health_ok,
        }

    if job_state == "FAILED" or job.get("status") == "failed":
        return {
            "state": "FAILED",
            "pct": 40,
            "tasks": tasks,
            "phases": [
                {"id": "trigger", "status": "success"},
                {"id": "build", "status": "failed"},
                {"id": "deploy", "status": "pending"},
                {"id": "verify", "status": "pending"},
            ],
        }

    if health == "SUCCESS" or (wait == "SUCCESS" and build_done):
        verify_status = "success" if health == "SUCCESS" else "running"
        phases = [
            {"id": "trigger", "status": "success"},
            {"id": "build", "status": "success"},
            {"id": "deploy", "status": "success"},
            {"id": "verify", "status": verify_status},
        ]
        pct = 100 if health == "SUCCESS" else 92
        state = "SUCCESS" if health == "SUCCESS" else "RUNNING"
        return {"state": state, "pct": pct, "tasks": tasks, "phases": phases}

    # Refresh: K8s job finished + GitOps commit in logs — pipeline already ran end-to-end
    if build_done and git_pushed and job.get("status") == "complete" and ex_state == "SUCCESS":
        phases = [
            {"id": "trigger", "status": "success"},
            {"id": "build", "status": "success"},
            {"id": "deploy", "status": "success"},
            {"id": "verify", "status": "success"},
        ]
        return {"state": "SUCCESS", "pct": 100, "tasks": tasks, "phases": phases}

    # Live app healthy — reflect reality even while Kestra wait-pipeline (90s) runs
    if live_health_ok and git_pushed:
        build_status = "success" if build_done else "running"
        return {
            "state": "SUCCESS" if build_done else "RUNNING",
            "pct": 100 if build_done else 88,
            "tasks": tasks,
            "phases": [
                {"id": "trigger", "status": "success"},
                {"id": "build", "status": build_status},
                {"id": "deploy", "status": "success"},
                {"id": "verify", "status": "success"},
            ],
            "live_health": True,
        }

    # GitOps commit pushed — ArgoCD sync starts while BuildKit may still be building
    if git_pushed and not build_done:
        return {
            "state": "RUNNING",
            "pct": 52,
            "tasks": tasks,
            "phases": [
                {"id": "trigger", "status": "success"},
                {"id": "build", "status": "running"},
                {"id": "deploy", "status": "running"},
                {"id": "verify", "status": "pending"},
            ],
            "live_health": live_health_ok,
        }

    if wait == "SUCCESS" or (git_pushed and build_done):
        return {
            "state": "RUNNING",
            "pct": 78,
            "tasks": tasks,
            "phases": [
                {"id": "trigger", "status": "success"},
                {"id": "build", "status": "success"},
                {"id": "deploy", "status": "success"},
                {"id": "verify", "status": "running"},
            ],
            "live_health": live_health_ok,
        }

    if build_done or job_state == "SUCCESS":
        return {
            "state": "RUNNING",
            "pct": 65,
            "tasks": tasks,
            "phases": [
                {"id": "trigger", "status": "success"},
                {"id": "build", "status": "success"},
                {"id": "deploy", "status": "running"},
                {"id": "verify", "status": "pending"},
            ],
        }

    return {
        "state": ex_state or "RUNNING",
        "pct": 40,
        "tasks": tasks,
        "phases": [
            {"id": "trigger", "status": "success"},
            {"id": "build", "status": "running" if job.get("status") == "running" else "pending"},
            {"id": "deploy", "status": "pending"},
            {"id": "verify", "status": "pending"},
        ],
    }


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
