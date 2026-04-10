"""Build once-daily task reminder intents."""

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


class TaskReminderService:
    """Build one task reminder intent per user per local day."""

    _last_emitted_local_days: dict[tuple[str, str], str] = {}

    @classmethod
    def clear_emitted_days(cls) -> None:
        """Reset in-process reminder dedupe state, mainly for tests."""
        cls._last_emitted_local_days.clear()

    @classmethod
    def build_daily_reminder(
        cls,
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        now: datetime | None = None,
    ) -> NotificationIntent | None:
        """Build a once-daily reminder for due and overdue work."""
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
        if overdue_count == 0 and due_today_count == 0:
            return None

        cls._last_emitted_local_days[(user_id, schedule_timezone)] = (
            local_date.isoformat()
        )
        return NotificationIntent(
            user_id=user_id,
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Task reminder",
            body=cls._build_summary(overdue_count, due_today_count),
            route="sidebar://tasks/today",
            metadata={
                "overdue_count": overdue_count,
                "due_today_count": due_today_count,
                "scope": "today",
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
    def _count_due_tasks(
        db: Session,
        *,
        user_id: str,
        comparator: str,
        local_date,
    ) -> int:
        """Count active due tasks for the requested local-date comparison."""
        query = db.query(func.count(Task.id)).filter(
            Task.user_id == user_id,
            Task.deleted_at.is_(None),
            Task.status.notin_(["completed", "trashed", "someday"]),
            Task.deadline.isnot(None),
        )
        if comparator == "overdue":
            query = query.filter(Task.deadline < local_date)
        else:
            query = query.filter(Task.deadline == local_date)
        return int(query.scalar() or 0)

    @staticmethod
    def _build_summary(overdue_count: int, due_today_count: int) -> str:
        """Build reminder copy for due-today and overdue work."""
        parts: list[str] = []
        if overdue_count:
            parts.append(
                f"{overdue_count} overdue {'task' if overdue_count == 1 else 'tasks'}"
            )
        if due_today_count:
            parts.append(
                f"{due_today_count} due today"
                if due_today_count == 1
                else f"{due_today_count} due today"
            )
        return " and ".join(parts) + "."
