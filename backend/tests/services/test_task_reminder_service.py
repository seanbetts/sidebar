from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import uuid4

from api.models.task import Task
from api.models.user_settings import UserSettings
from api.services.task_reminder_delivery_state_service import (
    TaskReminderDeliveryStateService,
)
from api.services.task_reminder_service import TaskReminderService


def _task(
    *,
    user_id: str,
    title: str,
    deadline: date | None,
    status: str = "active",
) -> Task:
    return Task(
        id=uuid4(),
        user_id=user_id,
        title=title,
        status=status,
        deadline=deadline,
    )


def test_configured_user_gets_at_most_one_reminder_batch_per_scheduled_day(test_db):
    test_db.add(UserSettings(user_id="user-123"))
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    first_reminders = TaskReminderService.build_daily_reminders(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    TaskReminderDeliveryStateService.mark_delivery_accepted(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
        delivery_key=str(first_reminders[0].delivery_key),
        accepted_at=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    assert TaskReminderDeliveryStateService.mark_batch_completed(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
        completed_at=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    test_db.commit()
    second_reminders = TaskReminderService.build_daily_reminders(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 30, tzinfo=UTC),
    )
    next_day_reminders = TaskReminderService.build_daily_reminders(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 16, 9, 0, tzinfo=UTC),
    )

    assert len(first_reminders) == 1
    assert second_reminders == ()
    assert len(next_day_reminders) == 1


def test_mixed_reminder_returns_ordered_due_tasks_and_one_overdue_summary(test_db):
    older = _task(
        user_id="user-123",
        title="First due task",
        deadline=date(2026, 1, 15),
    )
    older.created_at = datetime(2026, 1, 1, 9, 0, tzinfo=UTC)
    newer = _task(
        user_id="user-123",
        title="Second due task",
        deadline=date(2026, 1, 15),
    )
    newer.created_at = datetime(2026, 1, 2, 9, 0, tzinfo=UTC)
    overdue = _task(
        user_id="user-123",
        title="Overdue task",
        deadline=date(2026, 1, 14),
    )
    test_db.add_all([newer, overdue, older])
    test_db.commit()

    evaluation = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert evaluation.reason == "ready"
    assert evaluation.due_today_count == 2
    assert evaluation.overdue_count == 1
    assert [intent.title for intent in evaluation.intents] == [
        "First due task",
        "Second due task",
        "1 task overdue",
    ]
    assert [intent.body for intent in evaluation.intents] == [
        "Due today",
        "Due today",
        "Open Today to review.",
    ]
    assert evaluation.intents[0].metadata == {
        "task_id": str(older.id),
        "task_title": "First due task",
        "account_id": "user-123",
        "scope": "today",
    }
    assert evaluation.intents[2].metadata == {
        "overdue_count": 1,
        "scope": "today",
    }


def test_due_today_only_returns_one_actionable_intent_per_task(test_db):
    task = _task(
        user_id="user-123",
        title="Quarterly review",
        deadline=date(2026, 1, 15),
    )
    test_db.add(task)
    test_db.commit()

    evaluation = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert len(evaluation.intents) == 1
    assert evaluation.intents[0].native_category == "TASK_REMINDER_ACTIONABLE"
    assert evaluation.intents[0].thread_id == "task-reminders"
    assert evaluation.intents[0].metadata["task_id"] == str(task.id)
    assert evaluation.intents[0].metadata["account_id"] == "user-123"
    assert evaluation.intents[0].delivery_key == f"ios:task:{task.id}"


def test_overdue_only_returns_navigation_summary_without_task_id(test_db):
    test_db.add(
        _task(
            user_id="user-123",
            title="Late task",
            deadline=date(2026, 1, 14),
        )
    )
    test_db.commit()

    evaluation = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert len(evaluation.intents) == 1
    assert evaluation.intents[0].title == "1 task overdue"
    assert evaluation.intents[0].native_category == "TASK_REMINDER_SUMMARY"
    assert evaluation.intents[0].thread_id == "task-reminders"
    assert "task_id" not in evaluation.intents[0].metadata
    assert "account_id" not in evaluation.intents[0].metadata
    assert evaluation.intents[0].delivery_key == "ios:overdue-summary"


def test_empty_reminder_evaluation_returns_no_intents(test_db):
    evaluation = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert evaluation.intents == ()
    assert evaluation.reason == "no_due_tasks"


def test_ineligible_task_states_and_soft_deletes_are_excluded(test_db):
    soft_deleted = _task(
        user_id="user-123",
        title="Deleted task",
        deadline=date(2026, 1, 15),
    )
    soft_deleted.deleted_at = datetime(2026, 1, 14, 9, 0, tzinfo=UTC)
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="Completed task",
                deadline=date(2026, 1, 15),
                status="completed",
            ),
            _task(
                user_id="user-123",
                title="Trashed task",
                deadline=date(2026, 1, 15),
                status="trashed",
            ),
            _task(
                user_id="user-123",
                title="Someday task",
                deadline=date(2026, 1, 15),
                status="someday",
            ),
            soft_deleted,
        ]
    )
    test_db.commit()

    evaluation = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert evaluation.intents == ()
    assert evaluation.reason == "no_due_tasks"


def test_invalid_timezone_and_emitted_day_return_no_intents(test_db):
    test_db.add(UserSettings(user_id="user-123"))
    test_db.add(
        _task(
            user_id="user-123",
            title="Due task",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    invalid = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Invalid/Timezone",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    TaskReminderDeliveryStateService.mark_delivery_accepted(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
        delivery_key="ios:task:due-task",
        accepted_at=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    assert TaskReminderDeliveryStateService.mark_batch_completed(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
        completed_at=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    test_db.commit()
    emitted = TaskReminderService.inspect_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert invalid.intents == ()
    assert invalid.reason == "invalid_timezone"
    assert emitted.intents == ()
    assert emitted.reason == "already_emitted"
