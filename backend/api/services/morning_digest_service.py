"""Build morning digest notification intents."""

from __future__ import annotations

from datetime import UTC, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import func
from sqlalchemy.orm import Session

from api.models.task import Task
from api.services.notification_types import (
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
)


class MorningDigestService:
    """Build one morning digest intent per user per local day."""

    _last_emitted_local_days: dict[tuple[str, str], str] = {}

    @classmethod
    def clear_emitted_days(cls) -> None:
        """Reset in-process digest dedupe state, mainly for tests."""
        cls._last_emitted_local_days.clear()

    @classmethod
    def mark_emitted_day(
        cls,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date_iso: str,
    ) -> None:
        """Record that a digest was successfully emitted for one local day."""
        cls._last_emitted_local_days[(user_id, schedule_timezone)] = local_date_iso

    @classmethod
    def build_digest(
        cls,
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        now: datetime | None = None,
    ) -> NotificationIntent | None:
        """Build the short morning digest notification payload for a user."""
        current_time = now or datetime.now(UTC)
        if current_time.tzinfo is None:
            current_time = current_time.replace(tzinfo=UTC)

        try:
            local_date = current_time.astimezone(ZoneInfo(schedule_timezone)).date()
        except ZoneInfoNotFoundError:
            return None

        if cls._already_emitted_for_day(
            user_id=user_id,
            schedule_timezone=schedule_timezone,
            local_date_iso=local_date.isoformat(),
        ):
            return None

        active_task_count = cls._count_active_tasks(db, user_id=user_id)
        if active_task_count == 0:
            return None

        overdue_count = cls._count_due_tasks(
            db,
            user_id=user_id,
            comparator="overdue",
            local_date=local_date,
        )
        due_today_count = cls._count_due_tasks(
            db,
            user_id=user_id,
            comparator="today",
            local_date=local_date,
        )
        focus_title = cls._find_focus_task_title(db, user_id=user_id)

        return NotificationIntent(
            user_id=user_id,
            category=NotificationCategory.MORNING_DIGEST,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Morning digest",
            body=cls._build_summary(
                overdue_count=overdue_count,
                due_today_count=due_today_count,
                active_task_count=active_task_count,
            ),
            route="sidebar://digest/morning",
            metadata={
                "overdue_count": overdue_count,
                "due_today_count": due_today_count,
                "active_task_count": active_task_count,
                "focus_title": focus_title,
                "scope": "morning_digest",
            },
        )

    @classmethod
    def _already_emitted_for_day(
        cls,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date_iso: str,
    ) -> bool:
        key = (user_id, schedule_timezone)
        return cls._last_emitted_local_days.get(key) == local_date_iso

    @staticmethod
    def _active_tasks_query(db: Session, *, user_id: str):
        """Return the base query for active user tasks."""
        return db.query(Task).filter(
            Task.user_id == user_id,
            Task.deleted_at.is_(None),
            Task.status.notin_(["completed", "trashed", "someday"]),
        )

    @classmethod
    def _count_active_tasks(cls, db: Session, *, user_id: str) -> int:
        """Count active tasks that are worth summarizing in the digest."""
        return int(
            cls._active_tasks_query(db, user_id=user_id)
            .with_entities(func.count(Task.id))
            .scalar()
            or 0
        )

    @classmethod
    def _count_due_tasks(
        cls,
        db: Session,
        *,
        user_id: str,
        comparator: str,
        local_date,
    ) -> int:
        """Count active due tasks for the requested local-date comparison."""
        query = cls._active_tasks_query(db, user_id=user_id).filter(
            Task.deadline.isnot(None)
        )
        if comparator == "overdue":
            query = query.filter(Task.deadline < local_date)
        else:
            query = query.filter(Task.deadline == local_date)
        return int(query.with_entities(func.count(Task.id)).scalar() or 0)

    @classmethod
    def _find_focus_task_title(cls, db: Session, *, user_id: str) -> str | None:
        """Return the first active task title to surface as digest context."""
        task = (
            cls._active_tasks_query(db, user_id=user_id)
            .order_by(
                Task.deadline.is_(None),
                Task.deadline.asc(),
                Task.created_at.asc(),
            )
            .first()
        )
        return str(task.title) if task else None

    @staticmethod
    def _build_summary(
        *,
        overdue_count: int,
        due_today_count: int,
        active_task_count: int,
    ) -> str:
        """Build a short digest summary for the notification body."""
        summary_parts: list[str] = []
        if overdue_count:
            summary_parts.append(f"{overdue_count} overdue")
        if due_today_count:
            summary_parts.append(f"{due_today_count} due today")
        summary_parts.append(
            f"{active_task_count} active task"
            if active_task_count == 1
            else f"{active_task_count} active tasks"
        )
        return ", ".join(summary_parts) + "."
