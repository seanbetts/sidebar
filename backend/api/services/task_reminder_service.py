"""Build once-daily task reminder intent batches."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import func
from sqlalchemy.orm import Query, Session

from api.models.task import Task
from api.services.notification_types import (
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
)

TASK_REMINDER_ACTIONABLE_CATEGORY = "TASK_REMINDER_ACTIONABLE"
TASK_REMINDER_SUMMARY_CATEGORY = "TASK_REMINDER_SUMMARY"
TASK_REMINDER_THREAD_ID = "task-reminders"


@dataclass(frozen=True, slots=True)
class TaskReminderEvaluation:
    """Expanded reminder batch evaluation used by scheduler diagnostics."""

    intents: tuple[NotificationIntent, ...]
    reason: str
    overdue_count: int
    due_today_count: int


class TaskReminderService:
    """Build one task reminder batch per user per local day."""

    _last_emitted_local_days: dict[tuple[str, str], str] = {}

    @classmethod
    def clear_emitted_days(cls) -> None:
        """Reset in-process reminder dedupe state, mainly for tests."""
        cls._last_emitted_local_days.clear()

    @classmethod
    def mark_emitted_day(
        cls,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date_iso: str,
    ) -> None:
        """Record that a reminder batch was emitted for one local day."""
        cls._last_emitted_local_days[(user_id, schedule_timezone)] = local_date_iso

    @classmethod
    def build_daily_reminders(
        cls,
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        now: datetime | None = None,
    ) -> tuple[NotificationIntent, ...]:
        """Build one daily batch for due-today and overdue work."""
        return cls.inspect_daily_reminder(
            db,
            user_id=user_id,
            schedule_timezone=schedule_timezone,
            now=now,
        ).intents

    @classmethod
    def inspect_daily_reminder(
        cls,
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        now: datetime | None = None,
    ) -> TaskReminderEvaluation:
        """Return the reminder batch plus the reason when it is empty."""
        current_time = now or datetime.now(UTC)
        if current_time.tzinfo is None:
            current_time = current_time.replace(tzinfo=UTC)

        try:
            local_date = current_time.astimezone(ZoneInfo(schedule_timezone)).date()
        except ZoneInfoNotFoundError:
            return TaskReminderEvaluation(
                intents=(),
                reason="invalid_timezone",
                overdue_count=0,
                due_today_count=0,
            )

        if cls._already_emitted_for_day(
            user_id=user_id,
            schedule_timezone=schedule_timezone,
            local_date_iso=local_date.isoformat(),
        ):
            return TaskReminderEvaluation(
                intents=(),
                reason="already_emitted",
                overdue_count=0,
                due_today_count=0,
            )

        due_today_tasks = cls._find_due_today_tasks(
            db,
            user_id=user_id,
            local_date=local_date,
        )
        due_today_count = len(due_today_tasks)
        overdue_count = cls._count_due_tasks(
            db,
            user_id=user_id,
            comparator="overdue",
            local_date=local_date,
        )

        intents = [
            NotificationIntent(
                user_id=user_id,
                category=NotificationCategory.TASK_REMINDER,
                delivery_mode=NotificationDeliveryMode.ALERT,
                title=str(task.title),
                body="Due today",
                route="sidebar://tasks/today",
                native_category=TASK_REMINDER_ACTIONABLE_CATEGORY,
                thread_id=TASK_REMINDER_THREAD_ID,
                metadata={
                    "task_id": str(task.id),
                    "task_title": str(task.title),
                    "scope": "today",
                },
            )
            for task in due_today_tasks
        ]
        if overdue_count > 0:
            overdue_title = (
                "1 task overdue"
                if overdue_count == 1
                else f"{overdue_count} tasks overdue"
            )
            intents.append(
                NotificationIntent(
                    user_id=user_id,
                    category=NotificationCategory.TASK_REMINDER,
                    delivery_mode=NotificationDeliveryMode.ALERT,
                    title=overdue_title,
                    body="Open Today to review.",
                    route="sidebar://tasks/today",
                    native_category=TASK_REMINDER_SUMMARY_CATEGORY,
                    thread_id=TASK_REMINDER_THREAD_ID,
                    metadata={
                        "overdue_count": overdue_count,
                        "scope": "today",
                    },
                )
            )

        if not intents:
            return TaskReminderEvaluation(
                intents=(),
                reason="no_due_tasks",
                overdue_count=0,
                due_today_count=0,
            )
        return TaskReminderEvaluation(
            intents=tuple(intents),
            reason="ready",
            overdue_count=overdue_count,
            due_today_count=due_today_count,
        )

    @classmethod
    def _already_emitted_for_day(
        cls,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date_iso: str,
    ) -> bool:
        """Return whether this user and timezone emitted on the local day."""
        key = (user_id, schedule_timezone)
        return cls._last_emitted_local_days.get(key) == local_date_iso

    @staticmethod
    def _active_tasks_query(db: Session, *, user_id: str) -> Query[Task]:
        """Return the base query for active user tasks."""
        return db.query(Task).filter(
            Task.user_id == user_id,
            Task.deleted_at.is_(None),
            Task.status.notin_(["completed", "trashed", "someday"]),
        )

    @classmethod
    def _find_due_today_tasks(
        cls,
        db: Session,
        *,
        user_id: str,
        local_date: date,
    ) -> list[Task]:
        """Return eligible due-today tasks in deterministic notification order."""
        return (
            cls._active_tasks_query(db, user_id=user_id)
            .filter(Task.deadline == local_date)
            .order_by(Task.created_at.asc(), Task.id.asc())
            .all()
        )

    @classmethod
    def _count_due_tasks(
        cls,
        db: Session,
        *,
        user_id: str,
        comparator: str,
        local_date: date,
    ) -> int:
        """Count active due tasks for the requested local-date comparison."""
        query = cls._active_tasks_query(db, user_id=user_id).filter(
            Task.deadline.isnot(None),
        )
        if comparator == "overdue":
            query = query.filter(Task.deadline < local_date)
        else:
            query = query.filter(Task.deadline == local_date)
        return int(query.with_entities(func.count(Task.id)).scalar() or 0)
