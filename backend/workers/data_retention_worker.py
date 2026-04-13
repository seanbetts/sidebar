"""Background worker for retention cleanup."""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import or_

from api import metrics
from api.config import settings
from api.db.session import SessionLocal, set_retention_worker_scope
from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.note import Note
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_operation_log import TaskOperationLog
from api.models.task_project import TaskProject
from api.models.user_ai_provider_key import UserAIProviderKey
from api.models.website import Website
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.content_retention_service import (
    CleanupTableSummary,
    ContentRetentionService,
)
from api.services.retention_policy import (
    full_retention_cutoff,
    retention_policy_for,
    total_retention_cutoff,
)

logger = logging.getLogger("retention.worker")


@dataclass
class CleanupRunSummary:
    """Aggregate results for one retention-cleanup cycle."""

    table_summaries: dict[str, CleanupTableSummary] = field(default_factory=dict)
    total_actions: int = 0

    def __post_init__(self) -> None:
        """Compute a default total when callers pass per-table summaries only."""
        if self.total_actions == 0:
            self.total_actions = sum(
                summary.tombstoned + summary.hard_deleted
                for summary in self.table_summaries.values()
            )


def _session_factory():
    """Return the configured session factory."""
    return SessionLocal


def run_retention_cycle(
    db,
    *,
    now: datetime | None = None,
    batch_size: int,
) -> CleanupRunSummary:
    """Run one retention pass across all managed tables."""
    current_now = now or datetime.now(UTC)
    table_summaries = {
        "notes": ContentRetentionService.prune_notes(
            db, now=current_now, limit=batch_size
        ),
        "websites": ContentRetentionService.prune_websites(
            db, now=current_now, limit=batch_size
        ),
        "ingested_files": ContentRetentionService.prune_ingested_files(
            db, now=current_now, limit=batch_size
        ),
        "tasks": ContentRetentionService.prune_tasks(
            db, now=current_now, limit=batch_size
        ),
        "user_ai_provider_keys": (
            ContentRetentionService.prune_user_ai_provider_keys(
                db, now=current_now, limit=batch_size
            )
        ),
    }
    table_summaries.update(
        ContentRetentionService.prune_operational_tables(
            db, now=current_now, limit=batch_size
        )
    )
    return CleanupRunSummary(table_summaries=table_summaries)


def _set_backlog_age(db, table_name: str, *, now: datetime) -> None:
    """Update the backlog-age gauge for one managed cleanup table."""
    oldest_timestamp: datetime | None = None

    if table_name == "notes":
        policy = retention_policy_for("notes")
        oldest_row = (
            db.query(Note.deleted_at)
            .filter(
                Note.deleted_at.is_not(None),
                or_(
                    Note.deleted_at <= total_retention_cutoff(policy, now=now),
                    (Note.deleted_at <= full_retention_cutoff(policy, now=now))
                    & Note.payload_purged_at.is_(None),
                ),
            )
            .order_by(Note.deleted_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None
    elif table_name == "websites":
        policy = retention_policy_for("websites")
        oldest_row = (
            db.query(Website.deleted_at)
            .filter(
                Website.deleted_at.is_not(None),
                or_(
                    Website.deleted_at <= total_retention_cutoff(policy, now=now),
                    (Website.deleted_at <= full_retention_cutoff(policy, now=now))
                    & Website.payload_purged_at.is_(None),
                ),
            )
            .order_by(Website.deleted_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None
    elif table_name == "ingested_files":
        policy = retention_policy_for("ingested_files")
        oldest_row = (
            db.query(IngestedFile.deleted_at)
            .filter(
                IngestedFile.deleted_at.is_not(None),
                IngestedFile.deleted_at <= total_retention_cutoff(policy, now=now),
            )
            .order_by(IngestedFile.deleted_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None
    elif table_name == "tasks":
        policy = retention_policy_for("tasks")
        candidates: list[datetime] = []
        for model in (Task, TaskProject, TaskGroup):
            oldest_row = (
                db.query(model.deleted_at)
                .filter(
                    model.deleted_at.is_not(None),
                    model.deleted_at <= total_retention_cutoff(policy, now=now),
                )
                .order_by(model.deleted_at.asc())
                .first()
            )
            if oldest_row:
                candidates.append(oldest_row[0])
        oldest_timestamp = min(candidates) if candidates else None
    elif table_name == "user_ai_provider_keys":
        policy = retention_policy_for("user_ai_provider_keys")
        oldest_row = (
            db.query(UserAIProviderKey.deleted_at)
            .filter(
                UserAIProviderKey.deleted_at.is_not(None),
                UserAIProviderKey.deleted_at <= total_retention_cutoff(policy, now=now),
            )
            .order_by(UserAIProviderKey.deleted_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None
    elif table_name == "website_processing_jobs":
        policy = retention_policy_for("website_processing_jobs")
        oldest_row = (
            db.query(WebsiteProcessingJob.updated_at)
            .filter(
                WebsiteProcessingJob.updated_at
                <= total_retention_cutoff(policy, now=now),
                WebsiteProcessingJob.status.in_(
                    ContentRetentionService._TERMINAL_WEBSITE_JOB_STATUSES
                ),
            )
            .order_by(WebsiteProcessingJob.updated_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None
    elif table_name == "file_processing_jobs":
        policy = retention_policy_for("file_processing_jobs")
        oldest_row = (
            db.query(FileProcessingJob.updated_at)
            .filter(
                FileProcessingJob.updated_at <= total_retention_cutoff(policy, now=now),
                FileProcessingJob.status.in_(
                    ContentRetentionService._TERMINAL_FILE_JOB_STATUSES
                ),
            )
            .order_by(FileProcessingJob.updated_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None
    elif table_name == "task_operation_log":
        policy = retention_policy_for("task_operation_log")
        oldest_row = (
            db.query(TaskOperationLog.created_at)
            .filter(
                TaskOperationLog.created_at <= total_retention_cutoff(policy, now=now)
            )
            .order_by(TaskOperationLog.created_at.asc())
            .first()
        )
        oldest_timestamp = oldest_row[0] if oldest_row else None

    age_seconds = 0.0
    if oldest_timestamp is not None:
        age_seconds = max((now - oldest_timestamp).total_seconds(), 0.0)
    metrics.data_cleanup_backlog_age_seconds.labels(table=table_name).set(age_seconds)


def _record_cleanup_metrics(db, summary: CleanupRunSummary, *, now: datetime) -> None:
    """Emit metrics for one cleanup cycle."""
    for table_name, table_summary in summary.table_summaries.items():
        if table_summary.tombstoned:
            metrics.data_cleanup_actions_total.labels(
                table=table_name,
                action="tombstoned",
                status="success",
            ).inc(table_summary.tombstoned)
        if table_summary.hard_deleted:
            metrics.data_cleanup_actions_total.labels(
                table=table_name,
                action="hard_deleted",
                status="success",
            ).inc(table_summary.hard_deleted)
        _set_backlog_age(db, table_name, now=now)


def run_once() -> CleanupRunSummary:
    """Run one cleanup cycle using configured worker settings."""
    start = time.perf_counter()
    current_now = datetime.now(UTC)
    try:
        session_factory = _session_factory()
        with session_factory() as db:
            set_retention_worker_scope(db, enabled=True)
            summary = run_retention_cycle(
                db,
                now=current_now,
                batch_size=settings.data_retention_batch_size,
            )
            _record_cleanup_metrics(db, summary, now=current_now)
        return summary
    finally:
        metrics.data_cleanup_duration_seconds.labels(phase="run_once").observe(
            time.perf_counter() - start
        )


def worker_loop() -> None:
    """Continuously run retention cleanup on the configured cadence."""
    while True:
        try:
            run_once()
        except Exception:
            logger.exception("Data retention worker crashed, retrying after delay")
        time.sleep(settings.data_retention_poll_seconds)
