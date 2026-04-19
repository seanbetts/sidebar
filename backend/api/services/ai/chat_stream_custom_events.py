"""Shared custom chat SSE event contract helpers."""

from __future__ import annotations

import json
import logging
from functools import lru_cache
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_FALLBACK_CUSTOM_CHAT_STREAM_EVENT_TYPES = frozenset(
    {
        "assistant_identity_updated",
        "assistant_soul_updated",
        "conversation_title_updated",
        "ingestion_updated",
        "memory_created",
        "memory_deleted",
        "memory_updated",
        "note_created",
        "note_deleted",
        "note_moved",
        "note_pinned",
        "note_updated",
        "onboarding_milestone_completed",
        "onboarding_provider_blocked",
        "onboarding_resume_suggested",
        "other_preferences_updated",
        "profile_user_settings_updated",
        "prompt_preview",
        "scratchpad_cleared",
        "scratchpad_updated",
        "tool_end",
        "tool_start",
        "ui_theme_set",
        "website_archived",
        "website_deleted",
        "website_pinned",
        "website_renamed",
        "website_saved",
        "workspace_patch",
    }
)


def _contract_path() -> Path:
    return (
        Path(__file__).resolve().parents[4]
        / "shared"
        / "contracts"
        / "chat_stream_custom_events.json"
    )


@lru_cache(maxsize=1)
def load_custom_chat_stream_event_types() -> frozenset[str]:
    """Load the declared custom SSE event types from the shared contract file."""
    contract_path = _contract_path()
    if not contract_path.exists():
        logger.warning(
            "Custom chat stream event contract missing at %s, using embedded fallback",
            contract_path,
        )
        return _FALLBACK_CUSTOM_CHAT_STREAM_EVENT_TYPES

    payload = json.loads(contract_path.read_text())
    raw_events = payload.get("custom_events")
    if not isinstance(raw_events, list):
        raise ValueError("chat_stream_custom_events.json must define custom_events")

    event_types: list[str] = []
    for raw_event in raw_events:
        if not isinstance(raw_event, str) or not raw_event.strip():
            raise ValueError("custom_events entries must be non-empty strings")
        event_types.append(raw_event.strip())

    return frozenset(event_types)


CUSTOM_CHAT_STREAM_EVENT_TYPES = load_custom_chat_stream_event_types()


def build_custom_chat_stream_event(
    event_type: str, data: dict[str, Any]
) -> dict[str, Any]:
    """Build a validated custom SSE event declared in the shared contract."""
    if event_type not in CUSTOM_CHAT_STREAM_EVENT_TYPES:
        raise ValueError(f"Unknown custom chat stream event type: {event_type}")
    return {"type": event_type, "data": data}
