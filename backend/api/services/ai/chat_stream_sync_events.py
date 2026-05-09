"""Builders for primitive chat stream sync events."""

from __future__ import annotations

from typing import Any

from api.services.ai.chat_stream_sync_protocol import (
    CHAT_STREAM_CHANGE_TYPES,
    CHAT_STREAM_ENTITY_TYPES,
    CUSTOM_CHAT_STREAM_EVENT_TYPES,
)


def _ensure_string(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty string")
    return value.strip()


def _normalize_string_list(values: Any, field_name: str) -> list[str]:
    if not isinstance(values, list):
        raise ValueError(f"{field_name} must be a list of strings")
    normalized: list[str] = []
    seen: set[str] = set()
    for value in values:
        item = _ensure_string(value, field_name)
        if item in seen:
            continue
        normalized.append(item)
        seen.add(item)
    if not normalized:
        raise ValueError(f"{field_name} must not be empty")
    return normalized


def _base_event(event_type: str, data: dict[str, Any]) -> dict[str, Any]:
    if event_type not in CUSTOM_CHAT_STREAM_EVENT_TYPES:
        raise ValueError(f"Unknown chat stream sync event type: {event_type}")
    return {"type": event_type, "data": data}


def _validate_entity_type(entity_type: str) -> str:
    normalized = _ensure_string(entity_type, "entity_type")
    if normalized not in CHAT_STREAM_ENTITY_TYPES:
        raise ValueError(f"Unknown chat stream entity type: {normalized}")
    return normalized


def _validate_change_type(change: str) -> str:
    normalized = _ensure_string(change, "change")
    if normalized not in CHAT_STREAM_CHANGE_TYPES:
        raise ValueError(f"Unknown chat stream change type: {normalized}")
    return normalized


def _normalize_metadata(
    *,
    tool_call_id: str | None,
    conversation_id: str | None,
) -> dict[str, str]:
    metadata: dict[str, str] = {}
    if isinstance(tool_call_id, str) and tool_call_id.strip():
        metadata["tool_call_id"] = tool_call_id.strip()
    if isinstance(conversation_id, str) and conversation_id.strip():
        metadata["conversation_id"] = conversation_id.strip()
    return metadata


def build_entity_changed(
    *,
    entity_type: str,
    entity_id: str,
    change: str,
    invalidate: list[str],
    patch: dict[str, Any] | None = None,
    tool_call_id: str | None = None,
    conversation_id: str | None = None,
) -> dict[str, Any]:
    """Build an `entity_changed` sync event."""
    normalized_entity_type = _validate_entity_type(entity_type)
    normalized_change = _validate_change_type(change)
    data: dict[str, Any] = {
        "entity_type": normalized_entity_type,
        "entity_id": _ensure_string(entity_id, "entity_id"),
        "change": normalized_change,
        "invalidate": _normalize_string_list(invalidate, "invalidate"),
    }
    if isinstance(patch, dict) and patch:
        data["patch"] = patch
    data.update(
        _normalize_metadata(
            tool_call_id=tool_call_id,
            conversation_id=conversation_id,
        )
    )
    return _base_event("entity_changed", data)


def build_entity_deleted(
    *,
    entity_type: str,
    entity_id: str,
    invalidate: list[str],
    tool_call_id: str | None = None,
    conversation_id: str | None = None,
) -> dict[str, Any]:
    """Build an `entity_deleted` sync event."""
    data: dict[str, Any] = {
        "entity_type": _validate_entity_type(entity_type),
        "entity_id": _ensure_string(entity_id, "entity_id"),
        "invalidate": _normalize_string_list(invalidate, "invalidate"),
    }
    data.update(
        _normalize_metadata(
            tool_call_id=tool_call_id,
            conversation_id=conversation_id,
        )
    )
    return _base_event("entity_deleted", data)


def build_collection_invalidated(
    *,
    targets: list[str],
    tool_call_id: str | None = None,
    conversation_id: str | None = None,
) -> dict[str, Any]:
    """Build a `collection_invalidated` sync event."""
    data: dict[str, Any] = {
        "targets": _normalize_string_list(targets, "targets"),
    }
    data.update(
        _normalize_metadata(
            tool_call_id=tool_call_id,
            conversation_id=conversation_id,
        )
    )
    return _base_event("collection_invalidated", data)


def build_tool_status(
    *,
    tool_call_id: str,
    status: str,
    display_name: str | None = None,
    summary: str | None = None,
) -> dict[str, Any]:
    """Build a `tool_status` sync event."""
    data: dict[str, Any] = {
        "tool_call_id": _ensure_string(tool_call_id, "tool_call_id"),
        "status": _ensure_string(status, "status"),
    }
    if isinstance(display_name, str) and display_name.strip():
        data["display_name"] = display_name.strip()
    if isinstance(summary, str) and summary.strip():
        data["summary"] = summary.strip()
    return _base_event("tool_status", data)


def build_tool_confirmation_requested(data: dict[str, Any]) -> dict[str, Any]:
    """Build a `tool_confirmation_requested` sync event."""
    required = {
        "confirmation_id",
        "tool_call_id",
        "tool_name",
        "parameters",
        "summary",
        "undo_supported",
        "expires_at",
    }
    missing = [field for field in required if field not in data]
    if missing:
        raise ValueError(f"Missing confirmation fields: {', '.join(missing)}")
    if not isinstance(data.get("parameters"), dict):
        raise ValueError("confirmation parameters must be a dictionary")
    return _base_event("tool_confirmation_requested", data)


def build_tool_confirmation_resolved(data: dict[str, Any]) -> dict[str, Any]:
    """Build a `tool_confirmation_resolved` sync event."""
    confirmation_id = _ensure_string(data.get("confirmation_id"), "confirmation_id")
    decision = _ensure_string(data.get("decision"), "decision")
    if decision not in {"accept", "decline"}:
        raise ValueError("confirmation decision must be accept or decline")
    resolved_at = _ensure_string(data.get("resolved_at"), "resolved_at")
    payload = {
        **data,
        "confirmation_id": confirmation_id,
        "decision": decision,
        "resolved_at": resolved_at,
    }
    return _base_event("tool_confirmation_resolved", payload)


def build_undo_available(data: dict[str, Any]) -> dict[str, Any]:
    """Build an `undo_available` sync event."""
    required = {"undo_token", "summary", "expires_at", "entity_type", "entity_id"}
    missing = [field for field in required if field not in data]
    if missing:
        raise ValueError(f"Missing undo fields: {', '.join(missing)}")
    payload = {
        **data,
        "undo_token": _ensure_string(data.get("undo_token"), "undo_token"),
        "summary": _ensure_string(data.get("summary"), "summary"),
        "expires_at": _ensure_string(data.get("expires_at"), "expires_at"),
        "entity_type": _ensure_string(data.get("entity_type"), "entity_type"),
        "entity_id": _ensure_string(data.get("entity_id"), "entity_id"),
    }
    return _base_event("undo_available", payload)


def build_workspace_patch(data: dict[str, Any]) -> dict[str, Any]:
    """Build a `workspace_patch` sync event."""
    if not isinstance(data, dict):
        raise ValueError("workspace patch payload must be a dictionary")
    version = data.get("version")
    operations = data.get("operations")
    if not isinstance(version, int) or isinstance(version, bool):
        raise ValueError("workspace patch payload version must be an integer")
    if not isinstance(operations, list):
        raise ValueError("workspace patch payload operations must be a list")
    return _base_event("workspace_patch", data)


def build_prompt_preview(data: dict[str, Any]) -> dict[str, Any]:
    """Build a `prompt_preview` sync event."""
    if not isinstance(data, dict):
        raise ValueError("prompt preview payload must be a dictionary")
    return _base_event("prompt_preview", data)


def build_sync_event(event_type: str, data: dict[str, Any]) -> dict[str, Any]:
    """Build any declared primitive sync event."""
    if event_type == "entity_changed":
        raise ValueError("Use build_entity_changed for entity_changed events")
    if event_type == "entity_deleted":
        raise ValueError("Use build_entity_deleted for entity_deleted events")
    if event_type == "collection_invalidated":
        raise ValueError(
            "Use build_collection_invalidated for collection_invalidated events"
        )
    if event_type == "tool_status":
        raise ValueError("Use build_tool_status for tool_status events")
    if event_type == "workspace_patch":
        raise ValueError("Use build_workspace_patch for workspace_patch events")
    if event_type == "prompt_preview":
        raise ValueError("Use build_prompt_preview for prompt_preview events")
    return _base_event(event_type, data)


__all__ = [
    "build_collection_invalidated",
    "build_entity_changed",
    "build_entity_deleted",
    "build_prompt_preview",
    "build_sync_event",
    "build_tool_confirmation_requested",
    "build_tool_confirmation_resolved",
    "build_tool_status",
    "build_undo_available",
    "build_workspace_patch",
]
