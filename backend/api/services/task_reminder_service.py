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
from api.services.task_reminder_delivery_state_service import (
    TaskReminderDeliveryStateService,
)

TASK_REMINDER_ACTIONABLE_CATEGORY = "TASK_REMINDER_ACTIONABLE"
TASK_REMINDER_SUMMARY_CATEGORY = "TASK_REMINDER_SUMMARY"
TASK_REMINDER_THREAD_ID = "task-reminders"


@dataclass(frozen=True, slots=True)
class ReminderFocusTask:
    """Minimal task context used to build legacy reminder copy."""

    id: str
    title: str
    scope: str


@dataclass(frozen=True, slots=True)
class TaskReminderEvaluation:
    """Expanded reminder batch evaluation used by scheduler diagnostics."""

    intents: tuple[NotificationIntent, ...]
    reason: str
    overdue_count: int
    due_today_count: int
    macos_intent: NotificationIntent | None = None
    accepted_delivery_keys: frozenset[str] = frozenset()


class TaskReminderService:
    """Build one task reminder batch per user per local day."""

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

        delivery_progress = TaskReminderDeliveryStateService.get_progress(
            db,
            user_id=user_id,
            schedule_timezone=schedule_timezone,
            local_date=local_date,
        )
        if delivery_progress.is_complete:
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
                    "account_id": user_id,
                    "scope": "today",
                },
                delivery_key=f"ios:task:{task.id}",
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
                    delivery_key="ios:overdue-summary",
                )
            )

        if not intents:
            return TaskReminderEvaluation(
                intents=(),
                reason="no_due_tasks",
                overdue_count=0,
                due_today_count=0,
                accepted_delivery_keys=delivery_progress.accepted_delivery_keys,
            )
        focus_task = cls._find_legacy_focus_task(
            db,
            user_id=user_id,
            local_date=local_date,
            due_today_tasks=due_today_tasks,
        )
        return TaskReminderEvaluation(
            intents=tuple(intents),
            reason="ready",
            overdue_count=overdue_count,
            due_today_count=due_today_count,
            macos_intent=(
                cls._build_legacy_summary_intent(
                    user_id=user_id,
                    focus_task=focus_task,
                    overdue_count=overdue_count,
                    due_today_count=due_today_count,
                )
                if focus_task is not None
                else None
            ),
            accepted_delivery_keys=delivery_progress.accepted_delivery_keys,
        )

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

    @classmethod
    def _find_legacy_focus_task(
        cls,
        db: Session,
        *,
        user_id: str,
        local_date: date,
        due_today_tasks: list[Task],
    ) -> ReminderFocusTask | None:
        """Return the focus task used by the unchanged macOS reminder summary."""
        if due_today_tasks:
            task = due_today_tasks[0]
            return ReminderFocusTask(
                id=str(task.id),
                title=str(task.title),
                scope="today",
            )

        overdue_task = (
            cls._active_tasks_query(db, user_id=user_id)
            .filter(Task.deadline.isnot(None), Task.deadline < local_date)
            .order_by(Task.deadline.asc(), Task.created_at.asc(), Task.id.asc())
            .first()
        )
        if overdue_task is None:
            return None
        return ReminderFocusTask(
            id=str(overdue_task.id),
            title=str(overdue_task.title),
            scope="overdue",
        )

    @classmethod
    def _build_legacy_summary_intent(
        cls,
        *,
        user_id: str,
        focus_task: ReminderFocusTask,
        overdue_count: int,
        due_today_count: int,
    ) -> NotificationIntent:
        """Build the pre-hybrid single reminder used only by macOS."""
        return NotificationIntent(
            user_id=user_id,
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title=cls._build_legacy_title(
                overdue_count=overdue_count,
                due_today_count=due_today_count,
            ),
            body=cls._build_legacy_body(
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
            delivery_key="macos:legacy-summary",
        )

    @staticmethod
    def _build_legacy_title(*, overdue_count: int, due_today_count: int) -> str:
        """Build the unchanged macOS task-reminder title."""
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
    def _build_legacy_body(
        *,
        focus_task: ReminderFocusTask,
        overdue_count: int,
        due_today_count: int,
    ) -> str:
        """Build the unchanged macOS task-reminder supporting copy."""
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
