"""Workspace-specific note operations for the notes API."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import or_
from sqlalchemy.orm import Session, load_only

from api.models.note import Note
from api.services.notes_service import NotesService, NoteNotFoundError
from sqlalchemy.orm.exc import ObjectDeletedError


class NotesWorkspaceService:
    """Workspace-facing note operations for the API layer."""

    @staticmethod
    def list_tree(db: Session, user_id: str) -> dict:
        """Return a notes tree for the UI.

        Args:
            db: Database session.
            user_id: Current user ID.

        Returns:
            Notes tree payload with children.
        """
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
        """Search notes and return UI-friendly results.

        Args:
            db: Database session.
            user_id: Current user ID.
            query: Search query string.
            limit: Max results to return. Defaults to 50.

        Returns:
            Search results payload.
        """
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
                    "pinned_order": metadata.get("pinned_order"),
                    "archived": NotesService.is_archived_folder(folder),
                }
            )

        return {"items": items}

    @staticmethod
    def create_folder(db: Session, user_id: str, path: str) -> dict:
        """Create a logical folder marker for notes.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Folder path to create.

        Returns:
            Folder creation result.
        """
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
        """Rename a folder and update note metadata paths.

        Args:
            db: Database session.
            user_id: Current user ID.
            old_path: Existing folder path.
            new_name: New folder name.

        Returns:
            Folder rename result.
        """
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
        """Move a folder to a new parent location.

        Args:
            db: Database session.
            user_id: Current user ID.
            old_path: Existing folder path.
            new_parent: Destination parent folder.

        Returns:
            Folder move result.

        Raises:
            ValueError: If destination is within the source.
        """
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
        """Soft delete all notes in a folder.

        Args:
            db: Database session.
            user_id: Current user ID.
            path: Folder path to delete.

        Returns:
            Folder deletion result.
        """
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
        """Fetch a note and format it for the API response.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note ID (UUID string).

        Returns:
            Note payload with content and metadata.

        Raises:
            ValueError: If note_id is invalid.
            NoteNotFoundError: If note is not found.
        """
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
        title: str | None = None,
        path: str = "",
        folder: str = "",
    ) -> dict:
        """Create a note using workspace request data.

        Args:
            db: Database session.
            user_id: Current user ID.
            content: Markdown content.
            path: Optional file path hint.
            folder: Optional folder override.

        Returns:
            Creation result payload.
        """
        resolved_folder = folder
        if not resolved_folder and path:
            folder_path = Path(path).parent.as_posix()
            resolved_folder = "" if folder_path == "." else folder_path

        created = NotesService.create_note(
            db,
            user_id,
            content,
            title=title,
            folder=resolved_folder
        )
        try:
            note_id = getattr(created, "_snapshot_id", created.id)
            updated_at = getattr(created, "_snapshot_updated_at", created.updated_at)
            modified = updated_at.timestamp() if updated_at else None
        except ObjectDeletedError:
            note_id = getattr(created, "_snapshot_id", None)
            updated_at = getattr(created, "_snapshot_updated_at", None)
            modified = updated_at.timestamp() if updated_at else None
        return {"success": True, "modified": modified, "id": str(note_id)}

    @staticmethod
    def update_note(db: Session, user_id: str, note_id: str, content: str) -> dict:
        """Update note content using workspace request data.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note ID (UUID string).
            content: Updated markdown content.

        Returns:
            Update result payload.
        """
        note_uuid = NotesService.parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note id")

        updated = NotesService.update_note(db, user_id, note_uuid, content)
        return {"success": True, "modified": updated.updated_at.timestamp(), "id": str(updated.id)}

    @staticmethod
    def rename_note(db: Session, user_id: str, note_id: str, new_name: str) -> dict:
        """Rename a note and update its content title.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note ID (UUID string).
            new_name: New filename or title.

        Returns:
            Rename result payload.

        Raises:
            ValueError: If note_id is invalid.
            NoteNotFoundError: If note is not found.
        """
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
        """Prepare a note for download.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note ID (UUID string).

        Returns:
            Download payload with content and filename.

        Raises:
            ValueError: If note_id is invalid.
            NoteNotFoundError: If note is not found.
        """
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
