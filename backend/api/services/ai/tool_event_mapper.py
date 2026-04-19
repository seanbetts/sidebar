"""Shared tool execution event mapping for chat orchestrators."""

from __future__ import annotations

import json
from typing import Any

from api.services.ai.chat_stream_custom_events import build_custom_chat_stream_event


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
        version = candidate.get("version")
        if not isinstance(version, int) or isinstance(version, bool):
            continue
        if not isinstance(candidate.get("operations"), list):
            continue
        events.append(build_custom_chat_stream_event("workspace_patch", candidate))
    return events


def assistant_settings_stream_event(
    display_name: str, result_data: dict[str, Any]
) -> dict[str, Any] | None:
    """Map assistant settings tool results to realtime stream events."""
    if display_name in {"Update Assistant Identity", "Reset Assistant Identity"}:
        return build_custom_chat_stream_event(
            "assistant_identity_updated",
            {
                "assistant_identity": result_data.get("assistant_identity"),
                "assistant_identity_meta": result_data.get("assistant_identity_meta"),
            },
        )
    if display_name in {"Update Assistant Soul", "Reset Assistant Soul"}:
        return build_custom_chat_stream_event(
            "assistant_soul_updated",
            {
                "assistant_soul": result_data.get("assistant_soul"),
                "assistant_soul_meta": result_data.get("assistant_soul_meta"),
            },
        )
    if display_name in {
        "Update Profile and User Settings",
        "Upload Profile Image",
        "Remove Profile Image",
    }:
        settings_payload = result_data.get("settings")
        data = settings_payload if isinstance(settings_payload, dict) else result_data
        return build_custom_chat_stream_event("profile_user_settings_updated", data)
    if display_name == "Set Other Preferences":
        return build_custom_chat_stream_event("other_preferences_updated", result_data)
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


def tool_side_effect_events(
    display_name: str, result: dict[str, Any]
) -> list[dict[str, Any]]:
    """Build side-effect stream events derived from successful tool results."""
    if not result.get("success"):
        return []

    result_data = result.get("data") or {}
    events: list[dict[str, Any]] = []

    if display_name == "Create Note":
        events.append(
            build_custom_chat_stream_event(
                "note_created",
                {
                    "id": result_data.get("id"),
                    "title": result_data.get("title"),
                    "folder": result_data.get("folder"),
                    "path": result_data.get("path"),
                    "open_in_workspace": True,
                },
            )
        )
    elif display_name == "Edit Note":
        events.append(
            build_custom_chat_stream_event(
                "note_updated",
                {
                    "id": result_data.get("id"),
                    "title": result_data.get("title"),
                    "name": result_data.get("name"),
                    "path": result_data.get("path"),
                    "content": result_data.get("content"),
                    "updated_at": result_data.get("updated_at"),
                },
            )
        )
    elif display_name == "Pin Note":
        events.append(
            build_custom_chat_stream_event(
                "note_pinned",
                {
                    "id": result_data.get("id"),
                    "pinned": result_data.get("pinned"),
                },
            )
        )
    elif display_name == "Move Note":
        events.append(
            build_custom_chat_stream_event(
                "note_moved",
                {
                    "id": result_data.get("id"),
                    "folder": result_data.get("folder"),
                },
            )
        )
    elif display_name in {"Transcribe Audio", "Transcribe YouTube"}:
        note_data = result_data.get("note") or {}
        if note_data.get("id"):
            events.append(
                build_custom_chat_stream_event(
                    "note_created",
                    {
                        "id": note_data.get("id"),
                        "title": note_data.get("title"),
                        "folder": note_data.get("folder"),
                    },
                )
            )
    elif display_name in {"Save Website", "Add Website"}:
        events.append(
            build_custom_chat_stream_event(
                "website_saved",
                {
                    "id": result_data.get("id"),
                    "title": result_data.get("title"),
                    "url": result_data.get("url"),
                },
            )
        )
    elif display_name == "Rename Website":
        events.append(
            build_custom_chat_stream_event(
                "website_renamed",
                {
                    "id": result_data.get("id"),
                    "title": result_data.get("title"),
                },
            )
        )
    elif display_name == "Pin Website":
        events.append(
            build_custom_chat_stream_event(
                "website_pinned",
                {
                    "id": result_data.get("id"),
                    "pinned": result_data.get("pinned"),
                },
            )
        )
    elif display_name == "Archive Website":
        events.append(
            build_custom_chat_stream_event(
                "website_archived",
                {
                    "id": result_data.get("id"),
                    "archived": result_data.get("archived"),
                },
            )
        )
    elif display_name == "Delete Note":
        events.append(
            build_custom_chat_stream_event(
                "note_deleted", {"id": result_data.get("id")}
            )
        )
    elif display_name == "Delete Website":
        events.append(
            build_custom_chat_stream_event(
                "website_deleted", {"id": result_data.get("id")}
            )
        )
    elif display_name in {"Write File", "Download YouTube"}:
        events.append(
            build_custom_chat_stream_event(
                "ingestion_updated", {"file_id": result_data.get("file_id")}
            )
        )
    elif display_name == "Set UI Theme":
        events.append(
            build_custom_chat_stream_event(
                "ui_theme_set", {"theme": result_data.get("theme")}
            )
        )
    elif display_name == "Update Scratchpad":
        events.append(
            build_custom_chat_stream_event(
                "scratchpad_updated", {"id": result_data.get("id")}
            )
        )
    elif display_name == "Clear Scratchpad":
        events.append(
            build_custom_chat_stream_event(
                "scratchpad_cleared", {"id": result_data.get("id")}
            )
        )
    elif display_name == "Generate Prompts":
        events.append(
            build_custom_chat_stream_event(
                "prompt_preview",
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
                },
            )
        )
    elif display_name == "Rename Conversation":
        events.append(
            build_custom_chat_stream_event(
                "conversation_title_updated",
                {
                    "id": result_data.get("id"),
                    "title": result_data.get("title"),
                    "titleGenerated": result_data.get("titleGenerated"),
                    "updatedAt": result_data.get("updatedAt"),
                },
            )
        )
    elif display_name == "Memory Tool":
        command = result_data.get("command")
        if command == "create":
            event_type = "memory_created"
        elif command == "delete":
            event_type = "memory_deleted"
        elif command in {"str_replace", "insert", "rename"}:
            event_type = "memory_updated"
        else:
            event_type = None
        if event_type:
            events.append(
                build_custom_chat_stream_event(event_type, {"result": result_data})
            )

    events.extend(workspace_patch_stream_events(result_data))

    assistant_event = assistant_settings_stream_event(display_name, result_data)
    if assistant_event:
        events.append(assistant_event)
    return events
