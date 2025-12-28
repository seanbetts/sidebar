"""Notes service for shared notes business logic."""
from __future__ import annotations

import re
import uuid
from datetime import datetime, timezone
from typing import Iterable, Optional

from sqlalchemy import or_
from sqlalchemy.orm import Session

from api.models.note import Note


class NoteNotFoundError(Exception):
    """Raised when a note is not found."""


class NotesService:
    """Service layer for notes operations."""

    H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)

    @staticmethod
    def extract_title(content: str, fallback: str) -> str:
        match = NotesService.H1_PATTERN.search(content or "")
        if match:
            return match.group(1).strip()
        return fallback

    @staticmethod
    def update_content_title(content: str, title: str) -> str:
        if NotesService.H1_PATTERN.search(content or ""):
            return NotesService.H1_PATTERN.sub(f"# {title}", content, count=1)
        return f"# {title}\n\n{content or ''}".strip() + "\n"

    @staticmethod
    def parse_note_id(value: str) -> uuid.UUID | None:
        try:
            return uuid.UUID(value)
        except (ValueError, TypeError):
            return None

    @staticmethod
    def is_archived_folder(folder: str) -> bool:
        return folder == "Archive" or folder.startswith("Archive/")

    @staticmethod
    def build_notes_tree(notes: Iterable[Note]) -> dict:
        root = {"name": "notes", "path": "/", "type": "directory", "children": [], "expanded": False}
        index: dict[str, dict] = {"": root}

        for note in notes:
            if note.title == "✏️ Scratchpad":
                continue
            metadata = note.metadata_ or {}
            folder = metadata.get("folder") or ""
            is_folder_marker = bool(metadata.get("folder_marker"))
            folder_parts = [part for part in folder.split("/") if part]
            current_path = ""
            current_node = root

            for part in folder_parts:
                current_path = f"{current_path}/{part}" if current_path else part
                if current_path not in index:
                    node = {
                        "name": part,
                        "path": f"folder:{current_path}",
                        "type": "directory",
                        "children": [],
                        "expanded": False
                    }
                    index[current_path] = node
                    current_node["children"].append(node)
                current_node = index[current_path]

            if is_folder_marker:
                continue

            is_archived = NotesService.is_archived_folder(folder)
            current_node["children"].append({
                "name": f"{note.title}.md",
                "path": str(note.id),
                "type": "file",
                "modified": note.updated_at.timestamp() if note.updated_at else None,
                "pinned": bool(metadata.get("pinned")),
                "archived": is_archived
            })

        def sort_children(node: dict) -> None:
            node["children"].sort(key=lambda item: (item.get("type") != "directory", item.get("name", "").lower()))
            for child in node["children"]:
                if child.get("type") == "directory":
                    sort_children(child)

        sort_children(root)
        return root

    @staticmethod
    def create_note(
        db: Session,
        user_id: str,
        content: str,
        *,
        title: Optional[str] = None,
        folder: str = "",
        pinned: bool = False,
        tags: Optional[list[str]] = None,
    ) -> Note:
        now = datetime.now(timezone.utc)
        resolved_title = title or NotesService.extract_title(content, "Untitled Note")
        metadata = {"folder": folder, "pinned": pinned}
        if tags:
            metadata["tags"] = tags

        note = Note(
            user_id=user_id,
            title=resolved_title,
            content=content,
            metadata_=metadata,
            created_at=now,
            updated_at=now,
            last_opened_at=None,
            deleted_at=None,
        )
        db.add(note)
        db.commit()
        db.refresh(note)
        return note

    @staticmethod
    def update_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        content: str,
        *,
        title: Optional[str] = None,
    ) -> Note:
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.id == note_id,
                Note.deleted_at.is_(None),
            )
            .first()
        )
        if not note:
            raise NoteNotFoundError(f"Note not found: {note_id}")

        resolved_title = title or NotesService.extract_title(content, note.title)
        note.title = resolved_title
        note.content = content
        note.updated_at = datetime.now(timezone.utc)
        db.commit()
        return note

    @staticmethod
    def update_folder(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        folder: str,
    ) -> Note:
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.id == note_id,
                Note.deleted_at.is_(None),
            )
            .first()
        )
        if not note:
            raise NoteNotFoundError(f"Note not found: {note_id}")

        note.metadata_ = {**(note.metadata_ or {}), "folder": folder}
        note.updated_at = datetime.now(timezone.utc)
        db.commit()
        return note

    @staticmethod
    def update_pinned(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        pinned: bool,
    ) -> Note:
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.id == note_id,
                Note.deleted_at.is_(None),
            )
            .first()
        )
        if not note:
            raise NoteNotFoundError(f"Note not found: {note_id}")

        note.metadata_ = {**(note.metadata_ or {}), "pinned": pinned}
        note.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(note)
        return note

    @staticmethod
    def delete_note(db: Session, user_id: str, note_id: uuid.UUID) -> bool:
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.id == note_id,
                Note.deleted_at.is_(None),
            )
            .first()
        )
        if not note:
            return False

        now = datetime.now(timezone.utc)
        note.deleted_at = now
        note.updated_at = now
        db.commit()
        return True

    @staticmethod
    def get_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        *,
        mark_opened: bool = True,
    ) -> Optional[Note]:
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.id == note_id,
                Note.deleted_at.is_(None),
            )
            .first()
        )
        if not note:
            return None

        if mark_opened:
            note.last_opened_at = datetime.now(timezone.utc)
            db.commit()
        return note

    @staticmethod
    def get_note_by_title(
        db: Session,
        user_id: str,
        title: str,
        *,
        mark_opened: bool = True,
    ) -> Optional[Note]:
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.title == title,
                Note.deleted_at.is_(None),
            )
            .first()
        )
        if not note:
            return None

        if mark_opened:
            note.last_opened_at = datetime.now(timezone.utc)
            db.commit()
        return note

    @staticmethod
    def list_notes(
        db: Session,
        user_id: str,
        *,
        folder: Optional[str] = None,
        pinned: Optional[bool] = None,
        archived: Optional[bool] = None,
        created_after: Optional[datetime] = None,
        created_before: Optional[datetime] = None,
        updated_after: Optional[datetime] = None,
        updated_before: Optional[datetime] = None,
        opened_after: Optional[datetime] = None,
        opened_before: Optional[datetime] = None,
        title_search: Optional[str] = None,
    ) -> Iterable[Note]:
        query = db.query(Note).filter(
            Note.user_id == user_id,
            Note.deleted_at.is_(None),
        )

        if folder is not None:
            query = query.filter(Note.metadata_["folder"].astext == folder)

        if pinned is not None:
            query = query.filter(Note.metadata_["pinned"].astext == str(pinned).lower())

        if archived is not None:
            archived_filter = or_(
                Note.metadata_["archived"].astext == str(archived).lower(),
                Note.metadata_["folder"].astext.like("Archive/%"),
                Note.metadata_["folder"].astext == "Archive",
            )
            query = query.filter(archived_filter if archived else ~archived_filter)

        if created_after is not None:
            query = query.filter(Note.created_at >= created_after)
        if created_before is not None:
            query = query.filter(Note.created_at <= created_before)
        if updated_after is not None:
            query = query.filter(Note.updated_at >= updated_after)
        if updated_before is not None:
            query = query.filter(Note.updated_at <= updated_before)
        if opened_after is not None:
            query = query.filter(Note.last_opened_at >= opened_after)
        if opened_before is not None:
            query = query.filter(Note.last_opened_at <= opened_before)

        if title_search:
            query = query.filter(Note.title.ilike(f"%{title_search}%"))

        return query.order_by(Note.updated_at.desc()).all()
