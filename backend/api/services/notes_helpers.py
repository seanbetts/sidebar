"""Helper utilities for note payloads and conflict detection."""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime
from typing import Any

from api.exceptions import ConflictError
from api.models.note import Note


def is_archived_folder(folder: str) -> bool:
    """Return True if a folder path is within Archive."""
    return folder == "Archive" or folder.startswith("Archive/")


def build_notes_tree(notes: Iterable[Note]) -> dict[str, Any]:
    """Build a hierarchical notes tree for UI display."""
    root: dict[str, Any] = {
        "name": "notes",
        "path": "/",
        "type": "directory",
        "children": [],
        "expanded": False,
    }
    index: dict[str, dict[str, Any]] = {"": root}

    for note in notes:
        if note.title == "✏️ Scratchpad":
            continue
        metadata = note.metadata_ or {}
        folder = metadata.get("folder") or ""
        is_folder_marker = bool(metadata.get("folder_marker"))
        folder_parts = [part for part in folder.split("/") if part]
        current_path = ""
        current_node: dict[str, Any] = root

        for part in folder_parts:
            current_path = f"{current_path}/{part}" if current_path else part
            if current_path not in index:
                node: dict[str, Any] = {
                    "name": part,
                    "path": f"folder:{current_path}",
                    "type": "directory",
                    "children": [],
                    "expanded": False,
                }
                index[current_path] = node
                current_node["children"].append(node)
            current_node = index[current_path]

        if is_folder_marker:
            current_node["folderMarker"] = True
            continue

        is_archived = is_archived_folder(folder)
        current_node["children"].append(
            {
                "name": f"{note.title}.md",
                "path": str(note.id),
                "type": "file",
                "modified": note.updated_at.timestamp() if note.updated_at else None,
                "pinned": bool(metadata.get("pinned")),
                "pinned_order": metadata.get("pinned_order"),
                "archived": is_archived,
            }
        )

    def sort_children(node: dict) -> None:
        """Sort tree children with folders first then by name."""
        node["children"].sort(
            key=lambda item: (
                item.get("type") != "directory",
                item.get("name", "").lower(),
            )
        )
        for child in node["children"]:
            if child.get("type") == "directory":
                sort_children(child)

    sort_children(root)
    return root


def note_sync_payload(note: Note) -> dict[str, object]:
    """Build a sync payload for a note."""
    metadata = note.metadata_ or {}
    folder = metadata.get("folder") or ""
    return {
        "id": str(note.id),
        "name": f"{note.title}.md",
        "content": note.content or "",
        "path": str(note.id),
        "modified": note.updated_at.timestamp() if note.updated_at else None,
        "folder": folder,
        "pinned": bool(metadata.get("pinned")),
        "pinned_order": metadata.get("pinned_order"),
        "archived": is_archived_folder(folder),
        "deleted_at": note.deleted_at.isoformat() if note.deleted_at else None,
    }


def note_conflict_payload(
    note: Note,
    *,
    op: str | None,
    client_updated_at: datetime | None,
    operation_id: str | None = None,
    reason: str | None = None,
) -> dict[str, object]:
    """Build a conflict payload for notes."""
    return {
        "operationId": operation_id,
        "op": op,
        "id": str(note.id),
        "clientUpdatedAt": client_updated_at.isoformat() if client_updated_at else None,
        "serverUpdatedAt": note.updated_at.isoformat() if note.updated_at else None,
        "serverNote": note_sync_payload(note),
        "reason": reason,
    }


def ensure_note_no_conflict(
    note: Note,
    client_updated_at: datetime | None,
    *,
    op: str,
) -> None:
    """Raise ConflictError when note updated after client timestamp."""
    if client_updated_at is None:
        return
    if note.updated_at and note.updated_at > client_updated_at:
        conflict = note_conflict_payload(
            note,
            op=op,
            client_updated_at=client_updated_at,
        )
        raise ConflictError(
            "Note has been updated since last sync", {"conflict": conflict}
        )
