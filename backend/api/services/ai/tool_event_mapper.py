"""Shared tool execution event mapping for chat orchestrators."""

from __future__ import annotations

import json
from typing import Any

from api.services.ai.chat_stream_sync_events import (
    build_collection_invalidated,
    build_entity_changed,
    build_entity_deleted,
    build_prompt_preview,
    build_workspace_patch,
)
from api.services.ai.tool_result_normalizer import normalize_tool_result

TASK_WRITE_TOOL_NAMES = {
    "Create Task",
    "Complete Task",
    "Rename Task",
    "Update Task Notes",
    "Defer Task",
    "Set Task Due Date",
    "Clear Task Due Date",
    "Set Task Repeat",
    "Create Project",
    "Rename Project",
    "Create Group",
    "Rename Group",
    "Delete Task",
    "Delete Project",
    "Delete Group",
    "Move Task",
}

INGESTION_WRITE_TOOL_NAMES = {
    "Write File",
    "Delete File",
    "Rename File",
    "Pin File",
    "Download YouTube",
    "Transcribe Audio",
    "Transcribe YouTube",
}


def workspace_patch_stream_events(result_data: dict[str, Any]) -> list[dict[str, Any]]:
    """Map workspace patch payloads from tool results to realtime stream events."""
    candidates: list[Any] = []
    patch = result_data.get("workspace_patch")
    if patch is not None:
        candidates.append(patch)

    patches = result_data.get("workspace_patches")
    if isinstance(patches, list):
        candidates.extend(patches)

    events: list[dict[str, Any]] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        try:
            events.append(build_workspace_patch(candidate))
        except ValueError:
            continue
    return events


def assistant_settings_stream_event(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    """Map assistant/settings tools to collection invalidation events."""
    if display_name in {"Update Assistant Identity", "Reset Assistant Identity"}:
        return build_collection_invalidated(targets=["assistant_settings"])
    if display_name in {"Update Assistant Soul", "Reset Assistant Soul"}:
        return build_collection_invalidated(targets=["assistant_settings"])
    if display_name in {
        "Update Profile and User Settings",
        "Upload Profile Image",
        "Remove Profile Image",
    }:
        return build_collection_invalidated(targets=["profile", "preferences"])
    if display_name == "Set Other Preferences":
        return build_collection_invalidated(targets=["preferences"])
    if display_name == "Set UI Theme":
        return build_collection_invalidated(targets=["preferences"])
    if display_name == "Memory Tool":
        command = str(result_data.get("command") or "").strip()
        if command in {"create", "delete", "str_replace", "insert", "rename"}:
            return build_collection_invalidated(targets=["memory"])
        return None
    if display_name in TASK_WRITE_TOOL_NAMES:
        return build_collection_invalidated(targets=["tasks"])
    if display_name in {"Update Scratchpad", "Clear Scratchpad"}:
        return build_collection_invalidated(targets=["scratchpad"])
    if display_name in INGESTION_WRITE_TOOL_NAMES:
        return build_collection_invalidated(targets=["ingestion"])
    if display_name in {
        "Create Note Folder",
        "Rename Note Folder",
        "Move Note Folder",
        "Delete Note Folder",
    }:
        return build_collection_invalidated(targets=["notes"])
    return None


def tool_result_content(display_name: str, result: dict[str, Any]) -> str:
    """Format tool result content for LLM tool-response turns."""
    content_value = json.dumps(result)
    if display_name == "Memory Tool":
        if result.get("success"):
            result_data = result.get("data") or {}
            content_value = result_data.get("content") or ""
        else:
            content_value = result.get("error") or "Unknown error"
    return content_value


def _note_entity_changed(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    entity_id = str(result_data.get("id") or result_data.get("note_id") or "").strip()
    if not entity_id:
        return None
    invalidate = ["notes", f"note:{entity_id}"]
    if display_name == "Get Note":
        patch = {
            "id": entity_id,
            "title": result_data.get("title"),
            "path": result_data.get("path"),
            "updated_at": result_data.get("updated_at"),
            "open_in_workspace": True,
        }
        return build_entity_changed(
            entity_type="note",
            entity_id=entity_id,
            change="opened",
            patch=patch,
            invalidate=invalidate,
        )
    if display_name == "Create Note":
        patch = {
            "id": entity_id,
            "title": result_data.get("title"),
            "folder": result_data.get("folder"),
            "path": result_data.get("path"),
            "open_in_workspace": True,
        }
        return build_entity_changed(
            entity_type="note",
            entity_id=entity_id,
            change="created",
            patch=patch,
            invalidate=invalidate,
        )
    if display_name == "Edit Note":
        patch = {
            "id": entity_id,
            "title": result_data.get("title"),
            "name": result_data.get("name"),
            "path": result_data.get("path"),
            "content": result_data.get("content"),
            "updated_at": result_data.get("updated_at"),
        }
        return build_entity_changed(
            entity_type="note",
            entity_id=entity_id,
            change="updated",
            patch=patch,
            invalidate=invalidate,
        )
    if display_name == "Pin Note":
        pinned = bool(result_data.get("pinned"))
        return build_entity_changed(
            entity_type="note",
            entity_id=entity_id,
            change="pinned" if pinned else "unpinned",
            patch={"id": entity_id, "pinned": pinned},
            invalidate=invalidate,
        )
    if display_name == "Move Note":
        return build_entity_changed(
            entity_type="note",
            entity_id=entity_id,
            change="moved",
            patch={"id": entity_id, "folder": result_data.get("folder")},
            invalidate=invalidate,
        )
    if display_name == "Archive Note":
        archived = bool(result_data.get("archived"))
        return build_entity_changed(
            entity_type="note",
            entity_id=entity_id,
            change="archived" if archived else "unarchived",
            patch={"id": entity_id, "archived": archived},
            invalidate=invalidate,
        )
    return None


def _website_entity_changed(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    entity_id = str(
        result_data.get("id") or result_data.get("website_id") or ""
    ).strip()
    if not entity_id:
        return None
    invalidate = ["websites", f"website:{entity_id}"]
    if display_name in {"Save Website", "Add Website"}:
        return build_entity_changed(
            entity_type="website",
            entity_id=entity_id,
            change="created",
            patch={
                "id": entity_id,
                "title": result_data.get("title"),
                "url": result_data.get("url"),
            },
            invalidate=invalidate,
        )
    if display_name == "Rename Website":
        return build_entity_changed(
            entity_type="website",
            entity_id=entity_id,
            change="renamed",
            patch={"title": result_data.get("title")},
            invalidate=invalidate,
        )
    if display_name == "Pin Website":
        pinned = bool(result_data.get("pinned"))
        return build_entity_changed(
            entity_type="website",
            entity_id=entity_id,
            change="pinned" if pinned else "unpinned",
            patch={"id": entity_id, "pinned": pinned},
            invalidate=invalidate,
        )
    if display_name == "Archive Website":
        archived = bool(result_data.get("archived"))
        return build_entity_changed(
            entity_type="website",
            entity_id=entity_id,
            change="archived" if archived else "unarchived",
            patch={"id": entity_id, "archived": archived},
            invalidate=invalidate,
        )
    return None


def _conversation_entity_changed(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    if display_name != "Rename Conversation":
        return None
    entity_id = str(
        result_data.get("id") or result_data.get("conversation_id") or ""
    ).strip()
    if not entity_id:
        return None
    return build_entity_changed(
        entity_type="conversation",
        entity_id=entity_id,
        change="renamed",
        patch={
            "title": result_data.get("title"),
            "titleGenerated": result_data.get("titleGenerated"),
            "updatedAt": result_data.get("updatedAt"),
        },
        invalidate=["conversations", f"conversation:{entity_id}"],
    )


def _note_delete_event(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    if display_name != "Delete Note":
        return None
    entity_id = str(result_data.get("id") or result_data.get("note_id") or "").strip()
    if not entity_id:
        return None
    return build_entity_deleted(
        entity_type="note",
        entity_id=entity_id,
        invalidate=["notes", f"note:{entity_id}"],
    )


def _website_delete_event(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    if display_name != "Delete Website":
        return None
    entity_id = str(
        result_data.get("id") or result_data.get("website_id") or ""
    ).strip()
    if not entity_id:
        return None
    return build_entity_deleted(
        entity_type="website",
        entity_id=entity_id,
        invalidate=["websites", f"website:{entity_id}"],
    )


def tool_side_effect_events(
    display_name: str, result: dict[str, Any]
) -> list[dict[str, Any]]:
    """Build side-effect stream events derived from successful tool results."""
    normalized = normalize_tool_result(display_name, result)
    if not normalized.get("success"):
        return []

    result_data = normalized.get("data") or {}
    events: list[dict[str, Any]] = []

    note_delete_event = _note_delete_event(display_name, result_data)
    if note_delete_event is not None:
        events.append(note_delete_event)
    else:
        note_event = _note_entity_changed(display_name, result_data)
        if note_event is not None:
            events.append(note_event)

    website_delete_event = _website_delete_event(display_name, result_data)
    if website_delete_event is not None:
        events.append(website_delete_event)
    else:
        website_event = _website_entity_changed(display_name, result_data)
        if website_event is not None:
            events.append(website_event)

    conversation_event = _conversation_entity_changed(display_name, result_data)
    if conversation_event is not None:
        events.append(conversation_event)

    if display_name == "Generate Prompts":
        events.append(
            build_prompt_preview(
                {
                    "system_prompt": result_data.get("system_prompt"),
                    "first_message_prompt": result_data.get("first_message_prompt"),
                    "system_prompt_sections": result_data.get("system_prompt_sections"),
                    "first_message_prompt_sections": result_data.get(
                        "first_message_prompt_sections"
                    ),
                    "prompt_report": result_data.get("prompt_report"),
                    "request_budget_report": result_data.get("request_budget_report"),
                    "workspace_context_menu_actions": result_data.get(
                        "workspace_context_menu_actions"
                    ),
                }
            )
        )

    events.extend(workspace_patch_stream_events(result_data))

    assistant_event = assistant_settings_stream_event(display_name, result_data)
    if assistant_event is not None:
        events.append(assistant_event)
    return events


__all__ = [
    "assistant_settings_stream_event",
    "tool_result_content",
    "tool_side_effect_events",
    "workspace_patch_stream_events",
]
