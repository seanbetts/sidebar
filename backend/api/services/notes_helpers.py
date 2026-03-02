"""Conflict helpers for notes writes."""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime

from api.exceptions import ConflictError
from api.models.note import Note


def build_notes_tree(notes: Iterable[Note]) -> dict[str, object]:
    """Build a hierarchical notes tree for UI payloads."""
    root: dict[str, object] = {
        "name": "notes",
        "path": "/",
        "type": "directory",
        "children": [],
        "expanded": False,
    }
    index: dict[str, dict[str, object]] = {"": root}

    for note in notes:
        if note.title == "✏️ Scratchpad":
            continue
        folder = (note.folder_path or "").strip("/")
        folder_parts = [part for part in folder.split("/") if part]
        current_path = ""
        current_node = root

        for part in folder_parts:
            current_path = f"{current_path}/{part}" if current_path else part
            if current_path not in index:
                node: dict[str, object] = {
                    "name": part,
                    "path": f"folder:{current_path}",
                    "type": "directory",
                    "children": [],
                    "expanded": False,
                }
                index[current_path] = node
                children = current_node.setdefault("children", [])
                if isinstance(children, list):
                    children.append(node)
            current_node = index[current_path]

        if note.is_folder_marker:
            current_node["folderMarker"] = True
            continue

        children = current_node.setdefault("children", [])
        if isinstance(children, list):
            children.append(
                {
                    "name": note.title,
                    "path": str(note.id),
                    "type": "file",
                    "modified": note.updated_at.timestamp()
                    if note.updated_at
                    else None,
                    "created": note.created_at.timestamp() if note.created_at else None,
                    "pinned": bool(note.pinned),
                    "pinned_order": note.pinned_order,
                    "archived": bool(note.is_archived),
                }
            )

    def sort_children(node: dict[str, object]) -> None:
        children = node.get("children")
        if not isinstance(children, list):
            return
        children.sort(
            key=lambda item: (
                item.get("type") != "directory",
                str(item.get("name", "")).lower(),
            )
        )
        for child in children:
            if isinstance(child, dict) and child.get("type") == "directory":
                sort_children(child)

    sort_children(root)
    return root


def _conflict_server_note_payload(note: Note) -> dict[str, object]:
    """Build a compact server-note payload for conflict responses."""
    return {
        "id": str(note.id),
        "title": note.title,
        "content": note.content or "",
        "plain_text": note.plain_text or "",
        "content_format": note.content_format or "rtf",
        "folder": (note.folder_path or "").strip("/"),
        "pinned": bool(note.pinned),
        "pinned_order": note.pinned_order,
        "archived": bool(note.is_archived),
        "is_folder_marker": bool(note.is_folder_marker),
        "deleted_at": note.deleted_at.isoformat() if note.deleted_at else None,
        "updated_at": note.updated_at.isoformat() if note.updated_at else None,
    }


def note_conflict_payload(
    note: Note,
    *,
    op: str | None,
    client_updated_at: datetime | None,
    operation_id: str | None = None,
    reason: str | None = None,
) -> dict[str, object]:
    """Build a conflict payload for stale note writes."""
    return {
        "operationId": operation_id,
        "op": op,
        "id": str(note.id),
        "clientUpdatedAt": client_updated_at.isoformat() if client_updated_at else None,
        "serverUpdatedAt": note.updated_at.isoformat() if note.updated_at else None,
        "serverNote": _conflict_server_note_payload(note),
        "reason": reason,
    }


def ensure_note_no_conflict(
    note: Note,
    client_updated_at: datetime | None,
    *,
    op: str,
) -> None:
    """Raise a conflict when the client writes stale note data."""
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
