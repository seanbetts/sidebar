"""Workspace-specific note operations for the notes API."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from typing import cast

from sqlalchemy.orm import Session, load_only
from sqlalchemy.orm.exc import ObjectDeletedError

from api.exceptions import BadRequestError, NoteNotFoundError
from api.models.note import Note
from api.schemas.filters import NoteFilters
from api.services.notes_document_types import (
    note_document_from_plain_text,
    project_plain_text_from_document,
)
from api.services.notes_helpers import build_notes_tree
from api.services.notes_service import NotesService
from api.services.notes_title import derive_note_title_from_document
from api.services.workspace_service import WorkspaceService
from api.utils.search import build_text_search_filter
from api.utils.validation import parse_uuid


class NotesWorkspaceService(WorkspaceService[Note]):
    """Workspace-facing note operations for the API layer."""

    @staticmethod
    def _parse_note_id(note_id: str):
        try:
            return parse_uuid(note_id, "note", "id")
        except BadRequestError:
            return None

    @staticmethod
    def _is_archive_folder(folder_path: str) -> bool:
        normalized = (folder_path or "").strip("/")
        return normalized == "Archive" or normalized.startswith("Archive/")

    @staticmethod
    def build_note_payload(note: Note, *, include_content: bool = True) -> dict:
        """Build a note payload for API responses."""
        document = note.document or note_document_from_plain_text(note.plain_text or "")
        _ = include_content
        payload = {
            "id": str(note.id),
            "title": note.title,
            "name": note.title,
            "path": str(note.id),
            "modified": note.updated_at.timestamp() if note.updated_at else None,
            "created": note.created_at.timestamp() if note.created_at else None,
            "document": document,
            "document_version": note.document_version,
            "plain_text": note.plain_text or "",
            "folder": note.folder_path or "",
            "pinned": bool(note.pinned),
            "pinned_order": note.pinned_order,
            "archived": bool(note.is_archived),
            "is_folder_marker": bool(note.is_folder_marker),
        }
        return payload

    @classmethod
    def _query_items(
        cls,
        db: Session,
        user_id: str,
        *,
        include_deleted: bool = False,
        include_archived: bool = True,
        **kwargs: object,
    ) -> list[Note]:
        query = db.query(Note).options(
            load_only(
                Note.id,
                Note.title,
                Note.document,
                Note.document_version,
                Note.plain_text,
                Note.folder_path,
                Note.pinned,
                Note.pinned_order,
                Note.is_folder_marker,
                Note.updated_at,
                Note.created_at,
                Note.is_archived,
            )
        )
        query = query.filter(Note.user_id == user_id)
        if not include_deleted:
            query = query.filter(Note.deleted_at.is_(None))
        if not include_archived:
            query = query.filter(Note.is_archived.is_(False))
        return query.order_by(Note.updated_at.desc()).all()

    @staticmethod
    def list_archived_tree(
        db: Session,
        user_id: str,
        *,
        limit: int = 200,
        offset: int = 0,
    ) -> dict[str, list[dict[str, object]]]:
        """Return a tree payload for archived notes only."""
        notes = NotesService.list_notes(
            db,
            user_id,
            NoteFilters(archived=True),
            limit=limit,
            offset=offset,
        )
        tree = build_notes_tree(notes)
        children = tree.get("children")
        if not isinstance(children, list):
            children = []
        return {"children": cast(list[dict[str, object]], children)}

    @classmethod
    def _build_tree(cls, items: list[Note], **kwargs: object) -> dict:
        return build_notes_tree(items)

    @classmethod
    def _search_items(
        cls,
        db: Session,
        user_id: str,
        query: str,
        *,
        limit: int,
        **kwargs: object,
    ) -> list[Note]:
        return (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.deleted_at.is_(None),
                Note.is_folder_marker.is_(False),
                build_text_search_filter(
                    [Note.title, Note.plain_text],
                    query,
                ),
            )
            .order_by(Note.updated_at.desc())
            .limit(limit)
            .all()
        )

    @classmethod
    def _item_to_dict(cls, item: Note, **kwargs: object) -> dict:
        return {
            "name": item.title,
            "path": str(item.id),
            "type": "file",
            "modified": item.updated_at.timestamp() if item.updated_at else None,
            "created": item.created_at.timestamp() if item.created_at else None,
            "pinned": bool(item.pinned),
            "pinned_order": item.pinned_order,
            "archived": bool(item.is_archived),
        }

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
        notes = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
            .all()
        )
        for note in notes:
            note_folder = (note.folder_path or "").strip("/")
            if note_folder == path or note_folder.startswith(f"{path}/"):
                return {"success": True, "exists": True}

        now = datetime.now(UTC)
        note = Note(
            user_id=user_id,
            title="__folder__",
            document=note_document_from_plain_text(""),
            document_version=1,
            plain_text="",
            folder_path=path,
            pinned=False,
            pinned_order=None,
            is_folder_marker=True,
            is_archived=NotesWorkspaceService._is_archive_folder(path),
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

        notes = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
            .all()
        )
        for note in notes:
            folder = (note.folder_path or "").strip("/")
            if folder == old_path or folder.startswith(f"{old_path}/"):
                updated_folder = folder.replace(old_path, new_folder, 1)
                note.folder_path = updated_folder
                note.is_archived = NotesWorkspaceService._is_archive_folder(
                    updated_folder
                )
                note.updated_at = datetime.now(UTC)
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
        if new_parent and (
            new_parent == old_path or new_parent.startswith(f"{old_path}/")
        ):
            raise ValueError("Invalid destination folder")

        basename = old_path.split("/")[-1]
        new_folder = f"{new_parent}/{basename}".strip("/") if new_parent else basename

        notes = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
            .all()
        )
        for note in notes:
            folder = (note.folder_path or "").strip("/")
            if folder == old_path or folder.startswith(f"{old_path}/"):
                updated_folder = folder.replace(old_path, new_folder, 1)
                note.folder_path = updated_folder
                note.is_archived = NotesWorkspaceService._is_archive_folder(
                    updated_folder
                )
                note.updated_at = datetime.now(UTC)
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
        notes = (
            db.query(Note)
            .filter(Note.user_id == user_id, Note.deleted_at.is_(None))
            .all()
        )
        now = datetime.now(UTC)
        for note in notes:
            note_folder = (note.folder_path or "").strip("/")
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
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")

        note = NotesService.get_note(db, user_id, note_uuid, mark_opened=True)
        if not note:
            raise NoteNotFoundError("Note not found")

        return NotesWorkspaceService.build_note_payload(note, include_content=True)

    @staticmethod
    def create_note(
        db: Session,
        user_id: str,
        document: dict[str, object],
        *,
        path: str = "",
        folder: str = "",
        client_id: str | None = None,
    ) -> dict:
        """Create a note using workspace request data.

        Args:
            db: Database session.
            user_id: Current user ID.
            document: Canonical semantic note document.
            path: Optional file path hint.
            folder: Optional folder override.
            client_id: Optional client-generated note ID.

        Returns:
            Creation result payload.
        """
        resolved_folder = folder
        if not resolved_folder and path:
            folder_path = Path(path).parent.as_posix()
            resolved_folder = "" if folder_path == "." else folder_path

        note_uuid = parse_uuid(client_id, "note", "id") if client_id else None
        created = NotesService.create_note(
            db,
            user_id,
            document,
            folder=resolved_folder,
            note_id=note_uuid,
        )
        try:
            return NotesWorkspaceService.build_note_payload(
                created, include_content=True
            )
        except ObjectDeletedError:
            note_id = getattr(created, "_snapshot_id", None)
            updated_at = getattr(created, "_snapshot_updated_at", None)
            fallback_document = document
            fallback_plain_text = project_plain_text_from_document(document)
            fallback_title = derive_note_title_from_document(fallback_document)
            return {
                "id": str(note_id),
                "title": fallback_title,
                "name": fallback_title,
                "path": str(note_id),
                "modified": updated_at.timestamp() if updated_at else None,
                "created": None,
                "document": fallback_document,
                "document_version": 1,
                "plain_text": fallback_plain_text,
                "folder": resolved_folder,
                "pinned": False,
                "pinned_order": None,
                "archived": NotesWorkspaceService._is_archive_folder(resolved_folder),
                "is_folder_marker": False,
            }

    @staticmethod
    def update_note(
        db: Session,
        user_id: str,
        note_id: str,
        document: dict[str, object],
        *,
        client_updated_at: datetime | None = None,
    ) -> dict:
        """Update note content using workspace request data.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note ID (UUID string).
            document: Canonical semantic note document.
            client_updated_at: Optional client timestamp for conflict checks.

        Returns:
            Update result payload.
        """
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")

        updated = NotesService.update_note(
            db,
            user_id,
            note_uuid,
            document,
            client_updated_at=client_updated_at,
        )
        return NotesWorkspaceService.build_note_payload(updated, include_content=True)

    @staticmethod
    def rename_note(
        db: Session,
        user_id: str,
        note_id: str,
        new_name: str,
        *,
        client_updated_at: datetime | None = None,
    ) -> dict:
        """Reject note rename requests because titles are derived from content.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note ID (UUID string).
            new_name: New filename or title.
            client_updated_at: Optional client timestamp for conflict checks.

        Returns:
            Rename result payload.

        Raises:
            ValueError: If note_id is invalid.
            NoteNotFoundError: If note is not found.
        """
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")

        _ = Path(new_name).name
        raise ValueError("Note titles are derived from note content")

    @staticmethod
    def update_pinned(
        db: Session,
        user_id: str,
        note_id: str,
        pinned: bool,
        *,
        client_updated_at: datetime | None = None,
    ) -> dict:
        """Update pinned state and return canonical note payload."""
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")
        updated = NotesService.update_pinned(
            db,
            user_id,
            note_uuid,
            pinned,
            client_updated_at=client_updated_at,
        )
        return NotesWorkspaceService.build_note_payload(updated, include_content=True)

    @staticmethod
    def move_note(
        db: Session,
        user_id: str,
        note_id: str,
        folder: str,
        *,
        client_updated_at: datetime | None = None,
    ) -> dict:
        """Move note to a new folder and return canonical note payload."""
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")
        updated = NotesService.update_folder(
            db,
            user_id,
            note_uuid,
            folder,
            client_updated_at=client_updated_at,
            op="move",
            clear_pinned=True,
        )
        return NotesWorkspaceService.build_note_payload(updated, include_content=True)

    @staticmethod
    def archive_note(
        db: Session,
        user_id: str,
        note_id: str,
        archived: bool,
        *,
        client_updated_at: datetime | None = None,
    ) -> dict:
        """Archive/unarchive note and return canonical note payload."""
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")
        folder = "Archive" if archived else ""
        updated = NotesService.update_folder(
            db,
            user_id,
            note_uuid,
            folder,
            client_updated_at=client_updated_at,
            op="archive",
            clear_pinned=archived,
        )
        return NotesWorkspaceService.build_note_payload(updated, include_content=True)

    @staticmethod
    def delete_note(
        db: Session,
        user_id: str,
        note_id: str,
        *,
        client_updated_at: datetime | None = None,
    ) -> dict:
        """Soft-delete note and return canonical payload."""
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")
        note = NotesService.get_note(db, user_id, note_uuid, mark_opened=False)
        if not note:
            raise NoteNotFoundError("Note not found")
        deleted = NotesService.delete_note(
            db,
            user_id,
            note_uuid,
            client_updated_at=client_updated_at,
        )
        if not deleted:
            raise NoteNotFoundError("Note not found")
        return NotesWorkspaceService.build_note_payload(note, include_content=True)

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
        note_uuid = NotesWorkspaceService._parse_note_id(note_id)
        if not note_uuid:
            raise ValueError("Invalid note ID")

        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id, Note.id == note_uuid, Note.deleted_at.is_(None)
            )
            .first()
        )
        if not note:
            raise NoteNotFoundError("Note not found")

        safe_plain_text = note.plain_text or ""
        filename = (
            note.title if note.title.lower().endswith(".txt") else f"{note.title}.txt"
        )
        return {
            "content": safe_plain_text,
            "filename": filename,
        }
