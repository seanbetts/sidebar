"""Workspace-specific note operations for the notes API."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import or_
from sqlalchemy.orm import Session, load_only

from api.models.note import Note
from api.services.notes_service import NotesService, NoteNotFoundError


class NotesWorkspaceService:
    @staticmethod
    def list_tree(db: Session, user_id: str) -> dict:
        notes = (
            db.query(Note)
            .options(load_only(Note.id, Note.title, Note.metadata_, Note.updated_at))
            .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
            .order_by(Note.updated_at.desc())
            .all()
        )
        tree = NotesService.build_notes_tree(notes)
        return {"children": tree.get("children", [])}

    @staticmethod
    def search(db: Session, user_id: str, query: str, *, limit: int = 50) -> dict:
        notes = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.deleted_at.is_(None),
                or_(
                    Note.title.ilike(f"%{query}%"),
                    Note.content.ilike(f"%{query}%"),
                ),
            )
            .order_by(Note.updated_at.desc())
            .limit(limit)
            .all()
        )

        items = []
        for note in notes:
            metadata = note.metadata_ or {}
            folder = metadata.get("folder") or ""
            items.append(
                {
                    "name": f"{note.title}.md",
                    "path": str(note.id),
                    "type": "file",
                    "modified": note.updated_at.timestamp() if note.updated_at else None,
                    "pinned": bool(metadata.get("pinned")),
                    "archived": NotesService.is_archived_folder(folder),
                }
            )

        return {"items": items}

    @staticmethod
    def create_folder(db: Session, user_id: str, path: str) -> dict:
        notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
        for note in notes:
            note_folder = (note.metadata_ or {}).get("folder") or ""
            if note_folder == path or note_folder.startswith(f"{path}/"):
                return {"success": True, "exists": True}

        now = datetime.now(timezone.utc)
        note = Note(
            user_id=user_id,
            title="__folder__",
            content="",
            metadata_={"folder": path, "pinned": False, "folder_marker": True},
            created_at=now,
            updated_at=now,
            last_opened_at=None,
            deleted_at=None,
        )
        db.add(note)
        db.commit()
        return {"success": True, "id": str(note.id)}

    @staticmethod
    def rename_folder(db: Session, user_id: str, old_path: str, new_name: str) -> dict:
        parent = "/".join(old_path.split("/")[:-1])
        new_folder = f"{parent}/{new_name}".strip("/") if parent else new_name

        notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
        for note in notes:
            folder = (note.metadata_ or {}).get("folder") or ""
            if folder == old_path or folder.startswith(f"{old_path}/"):
                updated_folder = folder.replace(old_path, new_folder, 1)
                note.metadata_ = {**(note.metadata_ or {}), "folder": updated_folder}
                note.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True, "newPath": f"folder:{new_folder}"}

    @staticmethod
    def move_folder(db: Session, user_id: str, old_path: str, new_parent: str) -> dict:
        if new_parent and (new_parent == old_path or new_parent.startswith(f"{old_path}/")):
            raise ValueError("Invalid destination folder")

        basename = old_path.split("/")[-1]
        new_folder = f"{new_parent}/{basename}".strip("/") if new_parent else basename

        notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
        for note in notes:
            folder = (note.metadata_ or {}).get("folder") or ""
            if folder == old_path or folder.startswith(f"{old_path}/"):
                updated_folder = folder.replace(old_path, new_folder, 1)
                note.metadata_ = {**(note.metadata_ or {}), "folder": updated_folder}
                note.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True, "newPath": f"folder:{new_folder}"}

    @staticmethod
    def delete_folder(db: Session, user_id: str, path: str) -> dict:
        notes = db.query(Note).filter(Note.user_id == user_id, Note.deleted_at.is_(None)).all()
        now = datetime.now(timezone.utc)
        for note in notes:
            note_folder = (note.metadata_ or {}).get("folder") or ""
            if note_folder == path or note_folder.startswith(f"{path}/"):
                note.deleted_at = now
                note.updated_at = now
        db.commit()
        return {"success": True}

    @staticmethod
    def get_note(db: Session, user_id: str, note_id: str) -> dict:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note id")

        note = NotesService.get_note(db, user_id, note_uuid, mark_opened=True)
        if not note:
            raise NoteNotFoundError("Note not found")

        return {
            "content": note.content,
            "name": f"{note.title}.md",
            "path": str(note.id),
            "modified": note.updated_at.timestamp() if note.updated_at else None,
        }

    @staticmethod
    def create_note(
        db: Session,
        user_id: str,
        content: str,
        *,
        path: str = "",
        folder: str = "",
    ) -> dict:
        resolved_folder = folder
        if not resolved_folder and path:
            folder_path = Path(path).parent.as_posix()
            resolved_folder = "" if folder_path == "." else folder_path

        created = NotesService.create_note(db, user_id, content, folder=resolved_folder)
        return {"success": True, "modified": created.updated_at.timestamp(), "id": str(created.id)}

    @staticmethod
    def update_note(db: Session, user_id: str, note_id: str, content: str) -> dict:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note id")

        updated = NotesService.update_note(db, user_id, note_uuid, content)
        return {"success": True, "modified": updated.updated_at.timestamp(), "id": str(updated.id)}

    @staticmethod
    def rename_note(db: Session, user_id: str, note_id: str, new_name: str) -> dict:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note id")

        note = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.id == note_uuid, Note.deleted_at.is_(None))
            .first()
        )
        if not note:
            raise NoteNotFoundError("Note not found")

        title = Path(new_name).stem
        note.title = title
        note.content = NotesService.update_content_title(note.content, title)
        note.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True, "newPath": str(note.id)}

    @staticmethod
    def download_note(db: Session, user_id: str, note_id: str) -> dict:
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note id")

        note = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.id == note_uuid, Note.deleted_at.is_(None))
            .first()
        )
        if not note:
            raise NoteNotFoundError("Note not found")

        return {
            "content": note.content or "",
            "filename": f"{note.title}.md",
        }
