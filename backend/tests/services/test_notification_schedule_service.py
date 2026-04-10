from __future__ import annotations

from datetime import UTC, datetime

from api.models.user_settings import UserSettings
from api.services.notification_schedule_service import NotificationScheduleService
from api.services.notification_types import NotificationCategory


def _settings_record(
    *,
    user_id: str,
    notification_preferences: dict,
) -> UserSettings:
    return UserSettings(
        user_id=user_id,
        notification_preferences=notification_preferences,
    )


def test_task_reminders_become_due_at_configured_local_time(test_db):
    NotificationScheduleService.clear_due_windows()
    test_db.add(
        _settings_record(
            user_id="user-london",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:30",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.commit()

    due = NotificationScheduleService.find_due_users(
        test_db,
        NotificationCategory.TASK_REMINDER,
        now=datetime(2026, 1, 15, 9, 30, tzinfo=UTC),
    )

    assert [recipient.user_id for recipient in due] == ["user-london"]


def test_morning_digest_requires_enablement_and_complete_schedule(test_db):
    NotificationScheduleService.clear_due_windows()
    test_db.add_all(
        [
            _settings_record(
                user_id="user-enabled",
                notification_preferences={
                    "morning_digest_enabled": True,
                    "morning_digest_time": "09:00",
                    "schedule_timezone": "Europe/London",
                },
            ),
            _settings_record(
                user_id="user-disabled",
                notification_preferences={
                    "morning_digest_enabled": False,
                    "morning_digest_time": "09:00",
                    "schedule_timezone": "Europe/London",
                },
            ),
            _settings_record(
                user_id="user-incomplete",
                notification_preferences={
                    "morning_digest_enabled": True,
                    "schedule_timezone": "Europe/London",
                },
            ),
        ]
    )
    test_db.commit()

    due = NotificationScheduleService.find_due_users(
        test_db,
        NotificationCategory.MORNING_DIGEST,
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert [recipient.user_id for recipient in due] == ["user-enabled"]


def test_timezone_aware_schedule_evaluation_respects_utc_offsets(test_db):
    NotificationScheduleService.clear_due_windows()
    test_db.add_all(
        [
            _settings_record(
                user_id="user-nyc",
                notification_preferences={
                    "task_reminders_enabled": True,
                    "task_reminder_time": "09:00",
                    "schedule_timezone": "America/New_York",
                },
            ),
            _settings_record(
                user_id="user-london",
                notification_preferences={
                    "task_reminders_enabled": True,
                    "task_reminder_time": "09:00",
                    "schedule_timezone": "Europe/London",
                },
            ),
        ]
    )
    test_db.commit()

    due = NotificationScheduleService.find_due_users(
        test_db,
        NotificationCategory.TASK_REMINDER,
        now=datetime(2026, 1, 15, 14, 0, tzinfo=UTC),
    )

    assert [recipient.user_id for recipient in due] == ["user-nyc"]


def test_due_results_are_deduped_within_same_scheduled_window(test_db):
    NotificationScheduleService.clear_due_windows()
    test_db.add(
        _settings_record(
            user_id="user-london",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:30",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.commit()
    now = datetime(2026, 1, 15, 9, 30, tzinfo=UTC)

    first_due = NotificationScheduleService.find_due_users(
        test_db,
        NotificationCategory.TASK_REMINDER,
        now=now,
    )
    second_due = NotificationScheduleService.find_due_users(
        test_db,
        NotificationCategory.TASK_REMINDER,
        now=now,
    )

    assert [recipient.user_id for recipient in first_due] == ["user-london"]
    assert second_due == []
