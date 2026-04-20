"""Persistence helpers for the scheduled notification worker heartbeat."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy.orm import Session

from api.models.notification_scheduler_heartbeat import NotificationSchedulerHeartbeat


class NotificationSchedulerHeartbeatService:
    """Read and write the latest scheduler loop status."""

    WORKER_NAME = "notification_schedule"

    @classmethod
    def get_status(cls, db: Session) -> NotificationSchedulerHeartbeat | None:
        """Return the latest persisted scheduler heartbeat row."""
        return db.get(NotificationSchedulerHeartbeat, cls.WORKER_NAME)

    @classmethod
    def mark_started(
        cls,
        db: Session,
        *,
        started_at: datetime,
    ) -> NotificationSchedulerHeartbeat:
        """Persist that a new scheduler loop iteration has started."""
        heartbeat = cls._get_or_create(db)
        heartbeat.last_started_at = started_at
        heartbeat.last_status = "running"
        heartbeat.last_error = None
        heartbeat.updated_at = datetime.now(UTC)
        db.add(heartbeat)
        return heartbeat

    @classmethod
    def mark_completed(
        cls,
        db: Session,
        *,
        started_at: datetime,
        completed_at: datetime,
        stats: dict[str, int],
    ) -> NotificationSchedulerHeartbeat:
        """Persist the latest successful scheduler loop iteration."""
        heartbeat = cls._get_or_create(db)
        heartbeat.last_started_at = started_at
        heartbeat.last_completed_at = completed_at
        heartbeat.last_status = "completed"
        heartbeat.last_error = None
        heartbeat.last_task_reminders_due = int(stats["task_reminders_due"])
        heartbeat.last_task_reminders_dispatched = int(
            stats["task_reminders_dispatched"]
        )
        heartbeat.last_morning_digests_due = int(stats["morning_digests_due"])
        heartbeat.last_morning_digests_dispatched = int(
            stats["morning_digests_dispatched"]
        )
        heartbeat.updated_at = datetime.now(UTC)
        db.add(heartbeat)
        return heartbeat

    @classmethod
    def mark_failed(
        cls,
        db: Session,
        *,
        started_at: datetime,
        failed_at: datetime,
        error_message: str,
    ) -> NotificationSchedulerHeartbeat:
        """Persist a failed scheduler loop iteration."""
        heartbeat = cls._get_or_create(db)
        heartbeat.last_started_at = started_at
        heartbeat.last_completed_at = failed_at
        heartbeat.last_status = "failed"
        heartbeat.last_error = error_message[:1000]
        heartbeat.updated_at = datetime.now(UTC)
        db.add(heartbeat)
        return heartbeat

    @classmethod
    def _get_or_create(cls, db: Session) -> NotificationSchedulerHeartbeat:
        heartbeat = db.get(NotificationSchedulerHeartbeat, cls.WORKER_NAME)
        if heartbeat is not None:
            return heartbeat
        heartbeat = NotificationSchedulerHeartbeat(worker_name=cls.WORKER_NAME)
        db.add(heartbeat)
        return heartbeat
