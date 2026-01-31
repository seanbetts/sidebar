"""Notes service for shared notes business logic."""

from __future__ import annotations

import re
import uuid
from collections.abc import Iterable
from datetime import UTC, datetime

from sqlalchemy import or_
from sqlalchemy.exc import InvalidRequestError
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy.orm.exc import ObjectDeletedError

from api.exceptions import BadRequestError, NoteNotFoundError
from api.models.note import Note
from api.schemas.filters import NoteFilters
from api.services.notes_helpers import ensure_note_no_conflict
from api.utils.metadata_helpers import get_max_pinned_order
from api.utils.pinned_order import lock_pinned_order
from api.utils.validation import parse_uuid


class NotesService:
    """Service layer for notes operations."""

    H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)

    @staticmethod
    def extract_title(content: str, fallback: str) -> str:
        """Extract the first H1 title from content.

        Args:
            content: Markdown content to scan.
            fallback: Fallback title if no H1 is present.

        Returns:
            Extracted title or fallback.
        """
        match = NotesService.H1_PATTERN.search(content or "")
        if match:
            return match.group(1).strip()
        return fallback

    @staticmethod
    def update_content_title(content: str, title: str) -> str:
        """Ensure the content has a leading H1 with the given title.

        Args:
            content: Markdown content to update.
            title: Title to inject or replace.

        Returns:
            Updated content with a leading H1.
        """
        if NotesService.H1_PATTERN.search(content or ""):
            return NotesService.H1_PATTERN.sub(f"# {title}", content, count=1)
        return f"# {title}\n\n{content or ''}".strip() + "\n"

    @staticmethod
    def parse_note_id(value: str) -> uuid.UUID | None:
        """Parse a UUID from a note ID string.

        Args:
            value: Note ID string.

        Returns:
            Parsed UUID or None if invalid.
        """
        try:
            return parse_uuid(value, "note", "id")
        except BadRequestError:
            return None

    @staticmethod
    def create_note(
        db: Session,
        user_id: str,
        content: str,
        *,
        title: str | None = None,
        folder: str = "",
        pinned: bool = False,
        tags: list[str] | None = None,
        note_id: uuid.UUID | None = None,
    ) -> Note:
        """Create a new note record.

        Args:
            db: Database session.
            user_id: Current user ID.
            content: Markdown content.
            title: Note title. Defaults to "Untitled Note" if not provided.
            folder: Folder path. Defaults to "".
            pinned: Whether the note is pinned. Defaults to False.
            tags: Optional list of tags.
            note_id: Optional note UUID for idempotent create.

        Returns:
            Newly created Note.
        """
        now = datetime.now(UTC)
        resolved_title = title or "Untitled Note"
        metadata = {"folder": folder, "pinned": pinned}
        if tags:
            metadata["tags"] = tags
        if note_id is not None:
            existing = (
                db.query(Note)
                .filter(Note.user_id == user_id, Note.id == note_id)
                .first()
            )
            if existing:
                if existing.deleted_at is not None:
                    existing.deleted_at = None
                    existing.title = resolved_title
                    existing.content = content
                    existing.metadata_ = metadata
                    flag_modified(existing, "metadata_")
                    existing.updated_at = now
                    db.commit()
                return existing

        note = Note(
            id=note_id or uuid.uuid4(),
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
        db.flush()
        snapshot_id = note.id
        db.commit()
        try:
            db.refresh(note)
            return note
        except (InvalidRequestError, ObjectDeletedError):
            # Fall back to a fresh query if refresh is blocked by RLS visibility.
            refreshed = (
                db.query(Note)
                .filter(
                    Note.user_id == user_id,
                    Note.id == snapshot_id,
                    Note.deleted_at.is_(None),
                )
                .first()
            )
            return refreshed or note

    @staticmethod
    def update_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        content: str,
        *,
        title: str | None = None,
        client_updated_at: datetime | None = None,
    ) -> Note:
        """Update a note's content and title.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note UUID.
            content: Updated markdown content.
            title: Optional explicit title. If not provided, existing title
                is preserved.
            client_updated_at: Optional client timestamp for conflict checks.

        Returns:
            Updated Note.

        Raises:
            NoteNotFoundError: If the note does not exist.
        """
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

        ensure_note_no_conflict(note, client_updated_at, op="update")

        if title is not None:
            note.title = title
        note.content = content
        note.updated_at = datetime.now(UTC)
        db.commit()
        return note

    @staticmethod
    def rename_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        title: str,
        *,
        client_updated_at: datetime | None = None,
    ) -> Note:
        """Rename a note by updating its title.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note UUID.
            title: New note title.
            client_updated_at: Optional client timestamp for conflict checks.

        Returns:
            Updated Note.

        Raises:
            NoteNotFoundError: If the note does not exist.
        """
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

        ensure_note_no_conflict(note, client_updated_at, op="rename")

        note.title = title
        note.updated_at = datetime.now(UTC)
        db.commit()
        return note

    @staticmethod
    def update_folder(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        folder: str,
        *,
        client_updated_at: datetime | None = None,
        op: str = "move",
    ) -> Note:
        """Update a note's folder.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note UUID.
            folder: New folder path.
            client_updated_at: Optional client timestamp for conflict checks.
            op: Operation label for conflict payloads.

        Returns:
            Updated Note.

        Raises:
            NoteNotFoundError: If the note does not exist.
        """
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

        ensure_note_no_conflict(note, client_updated_at, op=op)

        note.metadata_ = {**(note.metadata_ or {}), "folder": folder}
        flag_modified(note, "metadata_")
        note.updated_at = datetime.now(UTC)
        db.commit()
        return note

    @staticmethod
    def update_pinned(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        pinned: bool,
        *,
        client_updated_at: datetime | None = None,
    ) -> Note:
        """Update a note's pinned status.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note UUID.
            pinned: Desired pinned state.
            client_updated_at: Optional client timestamp for conflict checks.

        Returns:
            Updated Note.

        Raises:
            NoteNotFoundError: If the note does not exist.
        """
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

        ensure_note_no_conflict(note, client_updated_at, op="pin")

        metadata = note.metadata_ or {}
        metadata["pinned"] = pinned
        if pinned:
            if metadata.get("pinned_order") is None:
                lock_pinned_order(db, user_id, "notes")
                metadata["pinned_order"] = get_max_pinned_order(db, Note, user_id) + 1
        else:
            metadata.pop("pinned_order", None)
        note.metadata_ = metadata
        flag_modified(note, "metadata_")
        note.updated_at = datetime.now(UTC)
        db.commit()
        db.refresh(note)
        return note

    @staticmethod
    def update_pinned_order(
        db: Session,
        user_id: str,
        note_ids: list[uuid.UUID],
    ) -> None:
        """Update pinned order for notes."""
        if not note_ids:
            return
        order_map = {note_id: index for index, note_id in enumerate(note_ids)}
        notes = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.deleted_at.is_(None),
                Note.id.in_(note_ids),
            )
            .all()
        )
        for note in notes:
            metadata = note.metadata_ or {}
            metadata["pinned"] = True
            metadata["pinned_order"] = order_map.get(note.id)
            note.metadata_ = metadata
            flag_modified(note, "metadata_")
            note.updated_at = datetime.now(UTC)
        db.commit()

    @staticmethod
    def delete_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        *,
        client_updated_at: datetime | None = None,
        allow_missing: bool = False,
    ) -> bool:
        """Soft delete a note by setting deleted_at.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note UUID.
            client_updated_at: Optional client timestamp for conflict checks.
            allow_missing: When True, treat missing notes as already deleted.

        Returns:
            True if the note was deleted, False if not found.
        """
        note = NotesService.soft_delete_note(
            db,
            user_id,
            note_id,
            client_updated_at=client_updated_at,
            allow_missing=allow_missing,
        )
        if note is None and allow_missing:
            return True
        return note is not None

    @staticmethod
    def soft_delete_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        *,
        client_updated_at: datetime | None = None,
        allow_missing: bool = False,
    ) -> Note | None:
        """Soft delete a note and return the record."""
        note = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.id == note_id,
            )
            .first()
        )
        if not note:
            return None
        if note.deleted_at is not None:
            return note

        ensure_note_no_conflict(note, client_updated_at, op="delete")

        now = datetime.now(UTC)
        note.deleted_at = now
        note.updated_at = now
        db.commit()
        return note

    @staticmethod
    def get_note(
        db: Session,
        user_id: str,
        note_id: uuid.UUID,
        *,
        mark_opened: bool = True,
        include_deleted: bool = False,
    ) -> Note | None:
        """Fetch a note by ID.

        Args:
            db: Database session.
            user_id: Current user ID.
            note_id: Note UUID.
            mark_opened: Whether to update last_opened_at. Defaults to True.
            include_deleted: Include soft-deleted notes when True.

        Returns:
            Note if found, otherwise None.
        """
        query = db.query(Note).filter(
            Note.user_id == user_id,
            Note.id == note_id,
        )
        if not include_deleted:
            query = query.filter(Note.deleted_at.is_(None))
        note = query.first()
        if not note:
            return None

        if mark_opened and note.deleted_at is None:
            note.last_opened_at = datetime.now(UTC)
            db.commit()
        return note

    @staticmethod
    def get_note_by_title(
        db: Session,
        user_id: str,
        title: str,
        *,
        mark_opened: bool = True,
    ) -> Note | None:
        """Fetch a note by title.

        Args:
            db: Database session.
            user_id: Current user ID.
            title: Note title.
            mark_opened: Whether to update last_opened_at. Defaults to True.

        Returns:
            Note if found, otherwise None.
        """
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
            note.last_opened_at = datetime.now(UTC)
            db.commit()
        return note

    @staticmethod
    def list_notes(
        db: Session,
        user_id: str,
        filters: NoteFilters | None = None,
        *,
        limit: int | None = None,
        offset: int | None = None,
    ) -> Iterable[Note]:
        """List notes using optional filters.

        Args:
            db: Database session.
            user_id: Current user ID.
            filters: Optional filters object.
            limit: Max results to return when provided.
            offset: Offset for pagination when provided.

        Returns:
            List of matching notes ordered by updated_at desc.
        """
        filters = filters or NoteFilters()
        query = db.query(Note).filter(
            Note.user_id == user_id,
            Note.deleted_at.is_(None),
        )

        if filters.folder is not None:
            query = query.filter(Note.metadata_["folder"].astext == filters.folder)

        if filters.pinned is not None:
            query = query.filter(
                Note.metadata_["pinned"].astext == str(filters.pinned).lower()
            )

        if filters.archived is not None:
            archived_filter = or_(
                Note.metadata_["archived"].astext == str(filters.archived).lower(),
                Note.metadata_["folder"].astext.like("Archive/%"),
                Note.metadata_["folder"].astext == "Archive",
            )
            query = query.filter(
                archived_filter if filters.archived else ~archived_filter
            )

        if filters.created_after is not None:
            query = query.filter(Note.created_at >= filters.created_after)
        if filters.created_before is not None:
            query = query.filter(Note.created_at <= filters.created_before)
        if filters.updated_after is not None:
            query = query.filter(Note.updated_at >= filters.updated_after)
        if filters.updated_before is not None:
            query = query.filter(Note.updated_at <= filters.updated_before)
        if filters.opened_after is not None:
            query = query.filter(Note.last_opened_at >= filters.opened_after)
        if filters.opened_before is not None:
            query = query.filter(Note.last_opened_at <= filters.opened_before)

        if filters.title_search:
            query = query.filter(Note.title.ilike(f"%{filters.title_search}%"))

        if offset:
            query = query.offset(offset)
        if limit:
            query = query.limit(limit)

        return query.order_by(Note.updated_at.desc()).all()
