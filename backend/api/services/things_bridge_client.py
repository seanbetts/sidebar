"""HTTP client for Things bridge calls."""
from __future__ import annotations

from typing import Any

import httpx
from fastapi import HTTPException, status

from api.config import settings
from api.models.things_bridge import ThingsBridge


class ThingsBridgeClient:
    """Client for calling a Things bridge instance."""

    def __init__(self, bridge: ThingsBridge):
        self.bridge = bridge
        self.base_url = bridge.base_url.rstrip("/")

    async def get_list(self, scope: str) -> dict[str, Any]:
        return await self._request("GET", f"/lists/{scope}")

    async def apply(self, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._request("POST", "/apply", json=payload)

    async def project_tasks(self, project_id: str) -> dict[str, Any]:
        return await self._request("GET", f"/projects/{project_id}/tasks")

    async def area_tasks(self, area_id: str) -> dict[str, Any]:
        return await self._request("GET", f"/areas/{area_id}/tasks")

    async def counts(self) -> dict[str, Any]:
        return await self._request("GET", "/counts")

    async def diagnostics(self) -> dict[str, Any]:
        return await self._request("GET", "/diagnostics")

    async def completed_today(self) -> dict[str, Any]:
        return await self._request("GET", "/completed/today")

    async def set_url_token(self, token: str) -> dict[str, Any]:
        return await self._request("POST", "/url-token", json={"token": token})

    async def _request(self, method: str, path: str, json: dict | None = None) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        headers = {"X-Things-Token": self.bridge.bridge_token}
        timeout = settings.things_bridge_timeout_seconds
        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.request(method, url, headers=headers, json=json)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Things bridge request failed: {exc}",
            ) from exc
        try:
            return response.json()
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Things bridge returned invalid JSON",
            ) from exc
