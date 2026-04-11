"""Timezone-aware due-user evaluation for scheduled notifications."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy.orm import Session

from api.models.user_settings import UserSettings
from api.services.notification_types import NotificationCategory
from api.services.settings_notifications import resolve_notification_preferences


@dataclass(frozen=True, slots=True)
class ScheduledNotificationRecipient:
    """A user that is due for a scheduled notification category."""

    user_id: str
    category: NotificationCategory
    scheduled_time: str
    schedule_timezone: str


@dataclass(frozen=True, slots=True)
class _ScheduledCategoryConfig:
    enabled_field: str
    time_field: str


class NotificationScheduleService:
    """Evaluate which users are due for scheduled notification categories."""

    SCHEDULED_CATEGORY_CONFIG = {
        NotificationCategory.TASK_REMINDER: _ScheduledCategoryConfig(
            enabled_field="task_reminders_enabled",
            time_field="task_reminder_time",
        ),
        NotificationCategory.MORNING_DIGEST: _ScheduledCategoryConfig(
            enabled_field="morning_digest_enabled",
            time_field="morning_digest_time",
        ),
    }
    _last_emitted_windows: dict[tuple[str, NotificationCategory], str] = {}

    @classmethod
    def clear_due_windows(cls) -> None:
        """Reset in-process dedupe state, mainly for tests."""
        cls._last_emitted_windows.clear()

    @classmethod
    def mark_emitted_window(
        cls,
        *,
        user_id: str,
        category: NotificationCategory,
        local_now: datetime,
        scheduled_time: str,
    ) -> None:
        """Record that a scheduled notification window was successfully delivered."""
        cls._last_emitted_windows[(user_id, category)] = cls._window_marker(
            local_now=local_now,
            scheduled_time=scheduled_time,
        )

    @classmethod
    def find_due_users(
        cls,
        db: Session,
        category: NotificationCategory,
        *,
        now: datetime | None = None,
    ) -> list[ScheduledNotificationRecipient]:
        """Return users due for the requested scheduled notification category."""
        if category not in cls.SCHEDULED_CATEGORY_CONFIG:
            return []

        current_time = now or datetime.now(UTC)
        if current_time.tzinfo is None:
            current_time = current_time.replace(tzinfo=UTC)

        config = cls.SCHEDULED_CATEGORY_CONFIG[category]
        due_users: list[ScheduledNotificationRecipient] = []
        settings_records = db.query(UserSettings).all()
        for settings_record in settings_records:
            preferences = resolve_notification_preferences(settings_record)
            if preferences.get(config.enabled_field) is not True:
                continue

            scheduled_time = preferences.get(config.time_field)
            schedule_timezone = preferences.get("schedule_timezone")
            if not scheduled_time or not schedule_timezone:
                continue

            try:
                local_now = current_time.astimezone(ZoneInfo(schedule_timezone))
            except ZoneInfoNotFoundError:
                continue

            if not cls._is_due_in_current_window(local_now, scheduled_time):
                continue

            if cls._was_emitted_in_window(
                user_id=settings_record.user_id,
                category=category,
                local_now=local_now,
                scheduled_time=scheduled_time,
            ):
                continue

            due_users.append(
                ScheduledNotificationRecipient(
                    user_id=settings_record.user_id,
                    category=category,
                    scheduled_time=scheduled_time,
                    schedule_timezone=schedule_timezone,
                )
            )

        return due_users

    @classmethod
    def _is_due_in_current_window(
        cls,
        local_now: datetime,
        scheduled_time: str,
    ) -> bool:
        """Return whether the current local wall-clock minute matches the schedule."""
        hour_text, minute_text = scheduled_time.split(":", 1)
        return local_now.hour == int(hour_text) and local_now.minute == int(minute_text)

    @classmethod
    def _was_emitted_in_window(
        cls,
        *,
        user_id: str,
        category: NotificationCategory,
        local_now: datetime,
        scheduled_time: str,
    ) -> bool:
        """Deduplicate repeated evaluations inside the same local scheduled window."""
        window_marker = cls._window_marker(
            local_now=local_now,
            scheduled_time=scheduled_time,
        )
        key = (user_id, category)
        return cls._last_emitted_windows.get(key) == window_marker

    @staticmethod
    def _window_marker(*, local_now: datetime, scheduled_time: str) -> str:
        """Build the unique key for one local scheduled-delivery minute."""
        return f"{local_now.date().isoformat()}:{scheduled_time}"
