"""Retention cleanup routines for soft-deleted content."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy.orm import Session

from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.note import Note
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_operation_log import TaskOperationLog
from api.models.task_project import TaskProject
from api.models.user_ai_provider_key import UserAIProviderKey
from api.models.website import Website
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.file_ingestion_service import FileIngestionService
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

    _TERMINAL_FILE_JOB_STATUSES = {"ready", "failed", "canceled"}
    _TERMINAL_WEBSITE_JOB_STATUSES = {"completed", "failed", "canceled"}

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

    @staticmethod
    def prune_ingested_files(
        db: Session, *, now: datetime, limit: int = 100
    ) -> CleanupTableSummary:
        """Hard-delete retained ingested-file metadata after retention expires."""
        policy = retention_policy_for("ingested_files")
        summary = CleanupTableSummary()
        delete_cutoff = total_retention_cutoff(policy, now=now)

        candidates = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.deleted_at.is_not(None),
                IngestedFile.deleted_at <= delete_cutoff,
            )
            .order_by(IngestedFile.deleted_at.asc())
            .limit(limit)
            .all()
        )
        for record in candidates:
            FileIngestionService.hard_delete_file_metadata(db, record.id)
            summary.hard_deleted += 1

        db.commit()
        return summary

    @staticmethod
    def prune_tasks(
        db: Session, *, now: datetime, limit: int = 100
    ) -> CleanupTableSummary:
        """Hard-delete soft-deleted task hierarchy rows after retention expires."""
        policy = retention_policy_for("tasks")
        delete_cutoff = total_retention_cutoff(policy, now=now)
        summary = CleanupTableSummary()

        for model in (Task, TaskProject, TaskGroup):
            candidates = (
                db.query(model)
                .filter(
                    model.deleted_at.is_not(None),
                    model.deleted_at <= delete_cutoff,
                )
                .order_by(model.deleted_at.asc())
                .limit(limit)
                .all()
            )
            for row in candidates:
                db.delete(row)
                summary.hard_deleted += 1

        db.commit()
        return summary

    @staticmethod
    def prune_user_ai_provider_keys(
        db: Session, *, now: datetime, limit: int = 100
    ) -> CleanupTableSummary:
        """Hard-delete soft-deleted provider keys after retention expires."""
        policy = retention_policy_for("user_ai_provider_keys")
        delete_cutoff = total_retention_cutoff(policy, now=now)
        summary = CleanupTableSummary()

        candidates = (
            db.query(UserAIProviderKey)
            .filter(
                UserAIProviderKey.deleted_at.is_not(None),
                UserAIProviderKey.deleted_at <= delete_cutoff,
            )
            .order_by(UserAIProviderKey.deleted_at.asc())
            .limit(limit)
            .all()
        )
        for record in candidates:
            db.delete(record)
            summary.hard_deleted += 1

        db.commit()
        return summary

    @staticmethod
    def prune_operational_tables(
        db: Session, *, now: datetime, limit: int = 100
    ) -> dict[str, CleanupTableSummary]:
        """Hard-delete stale operational rows using table-specific policies."""
        summaries = {
            "website_processing_jobs": CleanupTableSummary(),
            "file_processing_jobs": CleanupTableSummary(),
            "task_operation_log": CleanupTableSummary(),
        }

        website_policy = retention_policy_for("website_processing_jobs")
        website_cutoff = total_retention_cutoff(website_policy, now=now)
        website_jobs = (
            db.query(WebsiteProcessingJob)
            .filter(
                WebsiteProcessingJob.updated_at <= website_cutoff,
                WebsiteProcessingJob.status.in_(
                    ContentRetentionService._TERMINAL_WEBSITE_JOB_STATUSES
                ),
            )
            .order_by(WebsiteProcessingJob.updated_at.asc())
            .limit(limit)
            .all()
        )
        for website_job in website_jobs:
            db.delete(website_job)
            summaries["website_processing_jobs"].hard_deleted += 1

        file_policy = retention_policy_for("file_processing_jobs")
        file_cutoff = total_retention_cutoff(file_policy, now=now)
        file_jobs = (
            db.query(FileProcessingJob)
            .filter(
                FileProcessingJob.updated_at <= file_cutoff,
                FileProcessingJob.status.in_(
                    ContentRetentionService._TERMINAL_FILE_JOB_STATUSES
                ),
            )
            .order_by(FileProcessingJob.updated_at.asc())
            .limit(limit)
            .all()
        )
        for file_job in file_jobs:
            db.delete(file_job)
            summaries["file_processing_jobs"].hard_deleted += 1

        log_policy = retention_policy_for("task_operation_log")
        log_cutoff = total_retention_cutoff(log_policy, now=now)
        logs = (
            db.query(TaskOperationLog)
            .filter(TaskOperationLog.created_at <= log_cutoff)
            .order_by(TaskOperationLog.created_at.asc())
            .limit(limit)
            .all()
        )
        for log in logs:
            db.delete(log)
            summaries["task_operation_log"].hard_deleted += 1

        db.commit()
        return summaries
