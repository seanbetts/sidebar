from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import uuid4

from api.models.task import Task
from api.models.user_settings import UserSettings
from api.services.device_token_service import DeviceTokenService
from api.services.morning_digest_service import MorningDigestService
from api.services.notification_schedule_service import NotificationScheduleService
from api.services.notification_types import PushNotificationSendResult
from api.services.push_notification_service import PushNotificationService
from api.services.task_reminder_service import TaskReminderService
from workers.notification_schedule_worker import process_once


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


def test_task_reminders_retry_within_same_window_after_unsuccessful_dispatch(test_db):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()
    test_db.add(
        UserSettings(
            user_id="user-123",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    dispatched_counts: list[int] = []

    def _failed_task_dispatcher(db, due_users, *, now=None):
        _ = db
        _ = now
        dispatched_counts.append(len(due_users))
        return 0

    first_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        task_dispatcher=_failed_task_dispatcher,
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )
    second_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        task_dispatcher=_failed_task_dispatcher,
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert first_stats["task_reminders_due"] == 1
    assert second_stats["task_reminders_due"] == 1
    assert dispatched_counts == [1, 1]


def test_successful_task_reminders_are_deduped_within_same_window(
    test_db,
    monkeypatch,
):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()
    captured_requests = []

    def _fake_send_requests(requests):
        captured_requests.extend(requests)
        return PushNotificationSendResult(
            attempted_count=len(requests),
            sent_count=len(requests),
            invalid_tokens=(),
        )

    monkeypatch.setattr(
        PushNotificationService,
        "send_requests",
        staticmethod(_fake_send_requests),
    )
    test_db.add(
        UserSettings(
            user_id="user-123",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-123",
        token="token-123",
        platform="ios",
        environment="dev",
        capabilities={},
    )
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    first_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )
    second_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert first_stats["task_reminders_due"] == 1
    assert second_stats["task_reminders_due"] == 0
    assert first_stats["task_reminders_dispatched"] == 1
    assert second_stats["task_reminders_dispatched"] == 0
    assert len(captured_requests) == 1
