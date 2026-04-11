from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import uuid4

from api.models.task import Task
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


def test_configured_user_gets_at_most_one_reminder_per_scheduled_day(test_db):
    TaskReminderService.clear_emitted_days()
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    first_reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    TaskReminderService.mark_emitted_day(
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date_iso="2026-01-15",
    )
    second_reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 30, tzinfo=UTC),
    )
    next_day_reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 16, 9, 0, tzinfo=UTC),
    )

    assert first_reminder is not None
    assert second_reminder is None
    assert next_day_reminder is not None


def test_reminder_payload_summarizes_due_today_and_overdue_work(test_db):
    TaskReminderService.clear_emitted_days()
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="Overdue item",
                deadline=date(2026, 1, 14),
            ),
            _task(
                user_id="user-123",
                title="Due today item",
                deadline=date(2026, 1, 15),
            ),
        ]
    )
    test_db.commit()

    reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert reminder is not None
    assert reminder.title == "1 task overdue"
    assert reminder.route == "sidebar://tasks/today"
    assert reminder.body == "Overdue item is overdue, plus 1 due today."
    assert reminder.metadata == {
        "overdue_count": 1,
        "due_today_count": 1,
        "focus_task_id": str(reminder.metadata["focus_task_id"]),
        "focus_task_title": "Overdue item",
        "focus_scope": "overdue",
        "scope": "today",
    }


def test_no_reminder_when_there_is_nothing_worth_surfacing(test_db):
    TaskReminderService.clear_emitted_days()
    test_db.add(
        _task(
            user_id="user-123",
            title="Upcoming item",
            deadline=date(2026, 1, 16),
        )
    )
    test_db.commit()

    reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert reminder is None


def test_overdue_only_reminder_uses_focus_task_copy(test_db):
    TaskReminderService.clear_emitted_days()
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="Pay rent",
                deadline=date(2026, 1, 14),
            ),
            _task(
                user_id="user-123",
                title="File expenses",
                deadline=date(2026, 1, 13),
            ),
        ]
    )
    test_db.commit()

    reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert reminder is not None
    assert reminder.title == "2 tasks overdue"
    assert reminder.body == "File expenses is overdue, plus 1 more."
    assert reminder.metadata["focus_task_title"] == "File expenses"
    assert reminder.metadata["focus_scope"] == "overdue"


def test_due_today_single_reminder_names_focus_task(test_db):
    TaskReminderService.clear_emitted_days()
    test_db.add(
        _task(
            user_id="user-123",
            title="Quarterly review",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert reminder is not None
    assert reminder.title == "1 task due today"
    assert reminder.body == "Quarterly review is due today."
    assert reminder.metadata["focus_task_title"] == "Quarterly review"
    assert reminder.metadata["focus_scope"] == "today"


def test_mixed_reminder_prefers_overdue_focus_task(test_db):
    TaskReminderService.clear_emitted_days()
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="Pay rent",
                deadline=date(2026, 1, 14),
            ),
            _task(
                user_id="user-123",
                title="Quarterly review",
                deadline=date(2026, 1, 15),
            ),
        ]
    )
    test_db.commit()

    reminder = TaskReminderService.build_daily_reminder(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert reminder is not None
    assert reminder.title == "1 task overdue"
    assert reminder.body == "Pay rent is overdue, plus 1 due today."
    assert reminder.metadata["focus_scope"] == "overdue"
