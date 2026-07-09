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


async def trigger_execution(
    client: httpx.AsyncClient,
    base_url: str,
    namespace: str,
    flow_id: str,
    inputs: dict[str, str] | None = None,
) -> httpx.Response:
    """Start a Kestra execution (1.3 API first, then legacy)."""
    base = base_url.rstrip("/")
    payload = inputs or {}
    form_data = {f"inputs.{key}": value for key, value in payload.items()}
    main_exec = f"{base}/api/v1/main/executions/{namespace}/{flow_id}"
    legacy_exec = f"{base}/api/v1/executions/{namespace}/{flow_id}"

    attempts: list[tuple[str, dict[str, Any]]] = [
        (main_exec, {}),
        (main_exec, {"params": payload}),
        (main_exec, {"data": form_data}),
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
