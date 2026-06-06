"""Build once-daily task reminder intents."""

from __future__ import annotations

from dataclasses import dataclass
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


@dataclass(frozen=True, slots=True)
class ReminderFocusTask:
    """Minimal task context used to build reminder copy."""

    id: str
    title: str
    scope: str


@dataclass(frozen=True, slots=True)
class TaskReminderEvaluation:
    """Expanded reminder evaluation used by scheduler diagnostics."""

    intent: NotificationIntent | None
    reason: str
    overdue_count: int
    due_today_count: int


class TaskReminderService:
    """Build one task reminder intent per user per local day."""

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
        """Record that a reminder was successfully emitted for one local day."""
        cls._last_emitted_local_days[(user_id, schedule_timezone)] = local_date_iso

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
        evaluation = cls.inspect_daily_reminder(
            db,
            user_id=user_id,
            schedule_timezone=schedule_timezone,
            now=now,
        )
        return evaluation.intent

    @classmethod
    def inspect_daily_reminder(
        cls,
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        now: datetime | None = None,
    ) -> TaskReminderEvaluation:
        """Return the reminder intent plus the reason when no intent is built."""
        current_time = now or datetime.now(UTC)
        if current_time.tzinfo is None:
            current_time = current_time.replace(tzinfo=UTC)

        try:
            local_date = current_time.astimezone(ZoneInfo(schedule_timezone)).date()
        except ZoneInfoNotFoundError:
            return TaskReminderEvaluation(
                intent=None,
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
                intent=None,
                reason="already_emitted",
                overdue_count=0,
                due_today_count=0,
            )

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
            return TaskReminderEvaluation(
                intent=None,
                reason="no_due_tasks",
                overdue_count=0,
                due_today_count=0,
            )
        focus_task = cls._find_focus_task(
            db,
            user_id=user_id,
            local_date=local_date,
        )
        if focus_task is None:
            return TaskReminderEvaluation(
                intent=None,
                reason="no_focus_task",
                overdue_count=overdue_count,
                due_today_count=due_today_count,
            )

        return TaskReminderEvaluation(
            intent=NotificationIntent(
                user_id=user_id,
                category=NotificationCategory.TASK_REMINDER,
                delivery_mode=NotificationDeliveryMode.ALERT,
                title=cls._build_title(
                    overdue_count=overdue_count,
                    due_today_count=due_today_count,
                ),
                body=cls._build_body(
                    focus_task=focus_task,
                    overdue_count=overdue_count,
                    due_today_count=due_today_count,
                ),
                route="sidebar://tasks/today",
                metadata={
                    "overdue_count": overdue_count,
                    "due_today_count": due_today_count,
                    "focus_task_id": focus_task.id,
                    "focus_task_title": focus_task.title,
                    "focus_scope": focus_task.scope,
                    "scope": "today",
                },
            ),
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
            Task.deadline.isnot(None),
        )
        if comparator == "overdue":
            query = query.filter(Task.deadline < local_date)
        else:
            query = query.filter(Task.deadline == local_date)
        return int(query.with_entities(func.count(Task.id)).scalar() or 0)

    @classmethod
    def _find_focus_task(
        cls,
        db: Session,
        *,
        user_id: str,
        local_date,
    ) -> ReminderFocusTask | None:
        """Return the most relevant due task to mention in reminder copy."""
        due_today_task = (
            cls._active_tasks_query(db, user_id=user_id)
            .filter(
                Task.deadline == local_date,
            )
            .order_by(
                Task.created_at.asc(),
                Task.id.asc(),
            )
            .first()
        )
        if due_today_task is not None:
            return ReminderFocusTask(
                id=str(due_today_task.id),
                title=str(due_today_task.title),
                scope="today",
            )

        overdue_task = (
            cls._active_tasks_query(db, user_id=user_id)
            .filter(
                Task.deadline.isnot(None),
                Task.deadline < local_date,
            )
            .order_by(
                Task.deadline.asc(),
                Task.created_at.asc(),
                Task.id.asc(),
            )
            .first()
        )
        if overdue_task is None:
            return None
        return ReminderFocusTask(
            id=str(overdue_task.id),
            title=str(overdue_task.title),
            scope="overdue",
        )

    @staticmethod
    def _build_title(*, overdue_count: int, due_today_count: int) -> str:
        """Build a short title around today's work when it exists."""
        if due_today_count:
            return (
                "1 task due today"
                if due_today_count == 1
                else f"{due_today_count} tasks due today"
            )
        return (
            "1 task overdue" if overdue_count == 1 else f"{overdue_count} tasks overdue"
        )

    @staticmethod
    def _build_body(
        *,
        focus_task: ReminderFocusTask,
        overdue_count: int,
        due_today_count: int,
    ) -> str:
        """Build short reminder copy around a concrete focus task."""
        if due_today_count:
            if focus_task.scope == "today":
                summary_parts = []
                remaining_due_today = due_today_count - 1
                if remaining_due_today == 1:
                    summary_parts.append("1 more due today")
                elif remaining_due_today > 1:
                    summary_parts.append(f"{remaining_due_today} more due today")
                if overdue_count == 1:
                    summary_parts.append("1 overdue")
                elif overdue_count > 1:
                    summary_parts.append(f"{overdue_count} overdue")
                if not summary_parts:
                    return f"{focus_task.title} is due today."
                return (
                    f"{focus_task.title} is due today, plus "
                    f"{' and '.join(summary_parts)}."
                )
            due_today_suffix = (
                "plus 1 due today"
                if due_today_count == 1
                else f"plus {due_today_count} due today"
            )
            return f"{focus_task.title} is overdue, {due_today_suffix}."

        if overdue_count == 1:
            return f"{focus_task.title} is overdue."
        return f"{focus_task.title} is overdue, plus {overdue_count - 1} more."
