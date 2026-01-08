"""Shared test helpers."""

from __future__ import annotations

from typing import Any


def error_message(response: Any) -> str:
    """Normalize error payload to a message string."""
    payload = response.json().get("error")
    if isinstance(payload, dict):
        return payload.get("message", "")
    return payload or ""
