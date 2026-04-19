"""Helpers for opt-in chat stream whitespace diagnostics."""

from __future__ import annotations

import os
from collections.abc import Mapping

CHAT_STREAM_DEBUG_ENVIRONMENT_VARIABLE = "SIDEBAR_CHAT_STREAM_DEBUG"


def is_chat_stream_debug_enabled(
    environment: Mapping[str, str] | None = None,
) -> bool:
    """Return True when chat stream debug diagnostics are explicitly enabled."""
    source = environment if environment is not None else os.environ
    return source.get(CHAT_STREAM_DEBUG_ENVIRONMENT_VARIABLE) == "1"


def visible_whitespace_preview(text: str, limit: int = 160) -> str:
    """Render control characters visibly and truncate long content previews."""
    escaped = (
        text.replace("\\", "\\\\")
        .replace("\r", r"\r")
        .replace("\n", r"\n")
        .replace("\t", r"\t")
    )
    if len(escaped) <= limit:
        return escaped
    return f"{escaped[:limit]}..."


__all__ = [
    "CHAT_STREAM_DEBUG_ENVIRONMENT_VARIABLE",
    "is_chat_stream_debug_enabled",
    "visible_whitespace_preview",
]
