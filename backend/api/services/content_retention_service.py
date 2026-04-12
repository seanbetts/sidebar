"""Retention cleanup routines for soft-deleted content."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.orm import Session

from api.models.note import Note
from api.models.website import Website
from api.services.notes_document_types import note_document_from_plain_text
from api.services.retention_policy import (
    full_retention_cutoff,
    retention_policy_for,
    total_retention_cutoff,
)


@dataclass
class CleanupTableSummary:
    """Summary of cleanup actions for one table."""

    tombstoned: int = 0
    hard_deleted: int = 0


class ContentRetentionService:
    """Apply retention policy to soft-deleted content tables."""

    @staticmethod
    def prune_notes(
        db: Session, *, now: datetime, limit: int = 100
    ) -> CleanupTableSummary:
        """Tombstone or delete soft-deleted notes within the batch limit."""
        policy = retention_policy_for("notes")
        summary = CleanupTableSummary()

        hard_delete_cutoff = total_retention_cutoff(policy, now=now)
        hard_delete_candidates = (
            db.query(Note)
            .filter(
                Note.deleted_at.is_not(None),
                Note.deleted_at <= hard_delete_cutoff,
            )
            .order_by(Note.deleted_at.asc())
            .limit(limit)
            .all()
        )
        for note in hard_delete_candidates:
            db.delete(note)
            summary.hard_deleted += 1

        remaining_limit = max(limit - summary.hard_deleted, 0)
        if remaining_limit == 0:
            db.commit()
            return summary

        tombstone_cutoff = full_retention_cutoff(policy, now=now)
        tombstone_candidates = (
            db.query(Note)
            .filter(
                Note.deleted_at.is_not(None),
                Note.deleted_at <= tombstone_cutoff,
                Note.deleted_at > hard_delete_cutoff,
                Note.payload_purged_at.is_(None),
            )
            .order_by(Note.deleted_at.asc())
            .limit(remaining_limit)
            .all()
        )
        for note in tombstone_candidates:
            note.document = note_document_from_plain_text(note.title or "")
            note.plain_text = ""
            note.payload_purged_at = now
            summary.tombstoned += 1

        db.commit()
        return summary

    @staticmethod
    def prune_websites(
        db: Session, *, now: datetime, limit: int = 100
    ) -> CleanupTableSummary:
        """Tombstone or delete soft-deleted websites within the batch limit."""
        policy = retention_policy_for("websites")
        summary = CleanupTableSummary()

        hard_delete_cutoff = total_retention_cutoff(policy, now=now)
        hard_delete_candidates = (
            db.query(Website)
            .filter(
                Website.deleted_at.is_not(None),
                Website.deleted_at <= hard_delete_cutoff,
            )
            .order_by(Website.deleted_at.asc())
            .limit(limit)
            .all()
        )
        for website in hard_delete_candidates:
            db.delete(website)
            summary.hard_deleted += 1

        remaining_limit = max(limit - summary.hard_deleted, 0)
        if remaining_limit == 0:
            db.commit()
            return summary

        tombstone_cutoff = full_retention_cutoff(policy, now=now)
        tombstone_candidates = (
            db.query(Website)
            .filter(
                Website.deleted_at.is_not(None),
                Website.deleted_at <= tombstone_cutoff,
                Website.deleted_at > hard_delete_cutoff,
                Website.payload_purged_at.is_(None),
            )
            .order_by(Website.deleted_at.asc())
            .limit(remaining_limit)
            .all()
        )
        for website in tombstone_candidates:
            website.content = ""
            website.payload_purged_at = now
            summary.tombstoned += 1

        db.commit()
        return summary
