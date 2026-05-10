"""Normalize assistant-facing tool results."""

from __future__ import annotations

from typing import Any

_INGESTION_COLLECTION_TOOL_NAMES = {
    "Write File",
    "Delete File",
    "Rename File",
    "Pin File",
    "Download YouTube",
    "Transcribe Audio",
    "Transcribe YouTube",
}

_COLLECTION_INVALIDATION_TOOL_NAMES = {
    "Set UI Theme",
    "Update Assistant Identity",
    "Reset Assistant Identity",
    "Update Assistant Soul",
    "Reset Assistant Soul",
    "Update Profile and User Settings",
    "Upload Profile Image",
    "Remove Profile Image",
    "Set Other Preferences",
    "Memory Tool",
    "Update Scratchpad",
    "Clear Scratchpad",
    *_INGESTION_COLLECTION_TOOL_NAMES,
}

_ENTITY_CHANGED_TOOL_NAMES = {
    "Create Note",
    "Get Note",
    "Edit Note",
    "Pin Note",
    "Move Note",
    "Archive Note",
    "Save Website",
    "Add Website",
    "Rename Website",
    "Pin Website",
    "Archive Website",
    "Rename Conversation",
}

_ENTITY_DELETED_TOOL_NAMES = {
    "Delete Note",
    "Delete Website",
}

_CURRENT_ENTITY_ID = "current"


def _result_data(result: dict[str, Any]) -> dict[str, Any] | None:
    data = result.get("data")
    return data if isinstance(data, dict) else None


def _copy_result(result: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(result)
    data = _result_data(result)
    if data is not None:
        normalized["data"] = dict(data)
    return normalized


def _entity_touch(
    *,
    entity_type: str,
    entity_id: str,
    change: str,
) -> dict[str, str]:
    return {
        "entity_type": entity_type,
        "entity_id": entity_id,
        "change": change,
    }


def _touches_for_note(display_name: str, data: dict[str, Any]) -> list[dict[str, str]]:
    entity_id = str(data.get("id") or data.get("note_id") or "current")
    if display_name == "Create Note":
        return [
            _entity_touch(entity_type="note", entity_id=entity_id, change="created")
        ]
    if display_name == "Get Note":
        return [_entity_touch(entity_type="note", entity_id=entity_id, change="opened")]
    if display_name == "Delete Note":
        return [
            _entity_touch(entity_type="note", entity_id=entity_id, change="deleted")
        ]
    if display_name == "Pin Note":
        change = "pinned" if data.get("pinned", True) else "unpinned"
        return [_entity_touch(entity_type="note", entity_id=entity_id, change=change)]
    if display_name == "Move Note":
        return [_entity_touch(entity_type="note", entity_id=entity_id, change="moved")]
    if display_name == "Archive Note":
        change = "archived" if data.get("archived", True) else "unarchived"
        return [_entity_touch(entity_type="note", entity_id=entity_id, change=change)]
    return [_entity_touch(entity_type="note", entity_id=entity_id, change="updated")]


def _touches_for_website(
    display_name: str, data: dict[str, Any]
) -> list[dict[str, str]]:
    entity_id = str(data.get("id") or data.get("website_id") or "current")
    if display_name in {"Add Website", "Save Website"}:
        change = "created"
    elif display_name == "Delete Website":
        change = "deleted"
    elif display_name == "Pin Website":
        change = "pinned" if data.get("pinned", True) else "unpinned"
    elif display_name == "Archive Website":
        change = "archived" if data.get("archived", True) else "unarchived"
    else:
        change = "renamed"
    return [_entity_touch(entity_type="website", entity_id=entity_id, change=change)]


def _touches_for_conversation(data: dict[str, Any]) -> list[dict[str, str]]:
    entity_id = str(data.get("id") or data.get("conversation_id") or "current")
    return [
        _entity_touch(
            entity_type="conversation",
            entity_id=entity_id,
            change="renamed",
        )
    ]


def _touches_for_collection(entity_type: str) -> list[dict[str, str]]:
    return [
        _entity_touch(
            entity_type=entity_type,
            entity_id=_CURRENT_ENTITY_ID,
            change="updated",
        )
    ]


def _collection_targets_for_display_name(
    display_name: str, data: dict[str, Any]
) -> list[str]:
    if display_name in {
        "Update Assistant Identity",
        "Reset Assistant Identity",
        "Update Assistant Soul",
        "Reset Assistant Soul",
    }:
        return ["assistant_settings"]
    if display_name in {
        "Update Profile and User Settings",
        "Upload Profile Image",
        "Remove Profile Image",
    }:
        return ["profile", "preferences"]
    if display_name in {"Set Other Preferences", "Set UI Theme"}:
        return ["preferences"]
    if display_name == "Memory Tool":
        return ["memory"]
    if display_name in {"Update Scratchpad", "Clear Scratchpad"}:
        return ["scratchpad"]
    if display_name in _INGESTION_COLLECTION_TOOL_NAMES:
        return ["ingestion"]
    if display_name in {
        "Create Note Folder",
        "Rename Note Folder",
        "Move Note Folder",
        "Delete Note Folder",
    }:
        return ["notes"]
    if display_name == "Generate Prompts":
        return []
    return [str(data.get("entity_type"))] if data.get("entity_type") else []


def _summary_for_entities(
    display_name: str, data: dict[str, Any], entities_touched: list[dict[str, str]]
) -> str:
    if display_name == "Create Note":
        title = data.get("title") or data.get("name") or "note"
        return f"Created note {title}"
    if display_name == "Get Note":
        title = data.get("title") or data.get("name") or "note"
        return f"Opened note {title}"
    if display_name == "Delete Note":
        return "Deleted note"
    if display_name == "Edit Note":
        return "Updated note"
    if display_name == "Pin Note":
        return "Pinned note" if data.get("pinned", True) else "Unpinned note"
    if display_name == "Move Note":
        return "Moved note"
    if display_name == "Archive Note":
        return "Archived note" if data.get("archived", True) else "Unarchived note"
    if display_name in {"Add Website", "Save Website"}:
        title = data.get("title") or data.get("url") or "website"
        return f"Created website {title}"
    if display_name == "Rename Website":
        title = data.get("title") or "website"
        return f"Renamed website to {title}"
    if display_name == "Delete Website":
        return "Deleted website"
    if display_name == "Pin Website":
        return "Pinned website" if data.get("pinned", True) else "Unpinned website"
    if display_name == "Archive Website":
        return (
            "Archived website" if data.get("archived", True) else "Unarchived website"
        )
    if display_name == "Rename Conversation":
        title = data.get("title") or "conversation"
        return f"Renamed conversation to {title}"
    if display_name in {
        "Update Assistant Identity",
        "Reset Assistant Identity",
    }:
        return "Updated assistant identity"
    if display_name in {"Update Assistant Soul", "Reset Assistant Soul"}:
        return "Updated assistant soul"
    if display_name == "Update Profile and User Settings":
        return "Updated profile and user settings"
    if display_name in {
        "Upload Profile Image",
        "Remove Profile Image",
    }:
        return "Updated profile image"
    if display_name == "Set Other Preferences":
        return "Updated other preferences"
    if display_name == "Set UI Theme":
        return "Updated UI theme"
    if display_name == "Memory Tool":
        command = str(data.get("command") or "update")
        return f"Updated memory ({command})"
    if display_name in {"Update Scratchpad", "Clear Scratchpad"}:
        return "Updated scratchpad"
    if display_name in _INGESTION_COLLECTION_TOOL_NAMES:
        return "Updated ingestion"
    if display_name in {
        "Create Note Folder",
        "Rename Note Folder",
        "Move Note Folder",
        "Delete Note Folder",
    }:
        return "Updated notes folders"
    if entities_touched:
        entity_type = entities_touched[0]["entity_type"].replace("_", " ")
        return f"Updated {entity_type}"
    return "Updated tool result"


def _enrich_mutating_result(
    display_name: str, data: dict[str, Any]
) -> tuple[str, list[dict[str, str]], dict[str, Any]] | None:
    if display_name in _ENTITY_CHANGED_TOOL_NAMES:
        if display_name in {
            "Create Note",
            "Get Note",
            "Edit Note",
            "Pin Note",
            "Move Note",
            "Archive Note",
        }:
            touches = _touches_for_note(display_name, data)
        elif display_name in {
            "Save Website",
            "Add Website",
            "Rename Website",
            "Pin Website",
            "Archive Website",
        }:
            touches = _touches_for_website(display_name, data)
        elif display_name == "Rename Conversation":
            touches = _touches_for_conversation(data)
        else:
            return None
        patch = dict(data)
        return _summary_for_entities(display_name, data, touches), touches, patch

    if display_name in _ENTITY_DELETED_TOOL_NAMES:
        entity_type = "note" if display_name == "Delete Note" else "website"
        entity_id = str(
            data.get("id") or data.get("note_id") or data.get("website_id") or "current"
        )
        touches = [
            _entity_touch(
                entity_type=entity_type, entity_id=entity_id, change="deleted"
            )
        ]
        patch = dict(data)
        return _summary_for_entities(display_name, data, touches), touches, patch

    if display_name in _COLLECTION_INVALIDATION_TOOL_NAMES:
        targets = _collection_targets_for_display_name(display_name, data)
        if not targets:
            return None
        touches = [
            _entity_touch(
                entity_type=target, entity_id=_CURRENT_ENTITY_ID, change="updated"
            )
            for target in targets
        ]
        patch = dict(data)
        return _summary_for_entities(display_name, data, touches), touches, patch

    return None


def normalize_tool_result(display_name: str, result: dict[str, Any]) -> dict[str, Any]:
    """Normalize a tool result for assistant consumption."""
    normalized = _copy_result(result)
    if not result.get("success"):
        return normalized

    data = _result_data(result)
    if data is None:
        return normalized

    enrichment = _enrich_mutating_result(display_name, data)
    if enrichment is None:
        return normalized

    summary, entities_touched, normalized_data = enrichment
    normalized["data"] = normalized_data
    if not normalized.get("summary"):
        normalized["summary"] = summary
    if not normalized.get("entities_touched"):
        normalized["entities_touched"] = entities_touched
    return normalized


__all__ = ["normalize_tool_result"]
