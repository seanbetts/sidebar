"""Helpers for explicit legacy note migration workflows."""

from __future__ import annotations

from sqlalchemy import func, or_
from sqlalchemy.orm import Session

from api.models.note import Note


class NotesLegacyMigrationService:
    """Select notes that still need semantic-document migration."""

    @staticmethod
    def list_notes_missing_semantic_documents(
        db: Session,
        user_id: str,
        *,
        limit: int | None = None,
    ) -> list[Note]:
        """Return active note rows whose semantic document is still missing."""
        query = (
            db.query(Note)
            .filter(
                Note.user_id == user_id,
                Note.deleted_at.is_(None),
                Note.is_folder_marker.is_(False),
                or_(
                    Note.document.is_(None),
                    func.jsonb_typeof(Note.document) == "null",
                ),
            )
            .order_by(Note.updated_at.desc())
        )
        if limit is not None:
            query = query.limit(limit)
        return query.all()

    @staticmethod
    def list_note_ids_missing_documents(
        db: Session,
        user_id: str,
        *,
        limit: int | None = None,
    ) -> list[str]:
        """Return active note IDs whose semantic document is still missing."""
        notes = NotesLegacyMigrationService.list_notes_missing_semantic_documents(
            db,
            user_id,
            limit=limit,
        )
        return [str(note.id) for note in notes]
