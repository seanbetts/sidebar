"""Write and read helpers for durable scheduler cycle history."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime

from sqlalchemy.orm import Session

from api.models.notification_scheduler_run import NotificationSchedulerRun


class NotificationSchedulerRunService:
    """Persist one immutable row for each scheduler cycle."""

    WORKER_NAME = "notification_schedule"
    RECENT_RUN_LIMIT = 20

    @classmethod
    def list_recent(
        cls,
        db: Session,
        *,
        limit: int | None = None,
    ) -> list[NotificationSchedulerRun]:
        """Return recent scheduler runs, newest first."""
        resolved_limit = limit or cls.RECENT_RUN_LIMIT
        return (
            db.query(NotificationSchedulerRun)
            .order_by(NotificationSchedulerRun.started_at.desc())
            .limit(resolved_limit)
            .all()
        )

    @classmethod
    def record_completed(
        cls,
        db: Session,
        *,
        started_at: datetime,
        completed_at: datetime,
        stats: Mapping[str, int],
    ) -> NotificationSchedulerRun:
        """Persist one completed scheduler cycle."""
        row = NotificationSchedulerRun(
            worker_name=cls.WORKER_NAME,
            started_at=started_at,
            completed_at=completed_at,
            status="completed",
            error=None,
            task_reminders_due=int(stats.get("task_reminders_due", 0) or 0),
            task_reminders_dispatched=int(
                stats.get("task_reminders_dispatched", 0) or 0
            ),
            morning_digests_due=int(stats.get("morning_digests_due", 0) or 0),
            morning_digests_dispatched=int(
                stats.get("morning_digests_dispatched", 0) or 0
            ),
        )
        db.add(row)
        db.flush()
        return row

    @classmethod
    def record_failed(
        cls,
        db: Session,
        *,
        started_at: datetime,
        failed_at: datetime,
        error_message: str,
    ) -> NotificationSchedulerRun:
        """Persist one failed scheduler cycle."""
        row = NotificationSchedulerRun(
            worker_name=cls.WORKER_NAME,
            started_at=started_at,
            completed_at=failed_at,
            status="failed",
            error=error_message,
            task_reminders_due=0,
            task_reminders_dispatched=0,
            morning_digests_due=0,
            morning_digests_dispatched=0,
        )
        db.add(row)
        db.flush()
        return row
