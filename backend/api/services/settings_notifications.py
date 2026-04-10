"""Notification settings helpers shared across settings and delivery services."""

from __future__ import annotations

from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException

NOTIFICATION_TIME_FORMAT = "%H:%M"
NOTIFICATION_PREFERENCE_FIELDS = (
    "task_reminders_enabled",
    "task_reminder_time",
    "morning_digest_enabled",
    "morning_digest_time",
    "assistant_reply_notifications_enabled",
    "assistant_proactive_notifications_enabled",
    "schedule_timezone",
)


def clean_notification_time(value: Any, field_name: str) -> str | None:
    """Validate and normalize an HH:MM local notification time."""
    if value is None:
        return None
    if not isinstance(value, str):
        raise HTTPException(
            status_code=400,
            detail=f"{field_name} must be a string in HH:MM format",
        )
    trimmed = value.strip()
    if not trimmed:
        return None
    try:
        parsed = datetime.strptime(trimmed, NOTIFICATION_TIME_FORMAT)
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"{field_name} must use HH:MM format",
        ) from exc
    return parsed.strftime(NOTIFICATION_TIME_FORMAT)


def clean_timezone(value: Any, field_name: str) -> str | None:
    """Validate and normalize an IANA timezone name."""
    if value is None:
        return None
    if not isinstance(value, str):
        raise HTTPException(
            status_code=400,
            detail=f"{field_name} must be a string",
        )
    trimmed = value.strip()
    if not trimmed:
        return None
    try:
        ZoneInfo(trimmed)
    except ZoneInfoNotFoundError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"{field_name} must be a valid IANA timezone",
        ) from exc
    return trimmed


def resolve_notification_preferences(settings_record) -> dict[str, Any]:
    """Resolve stored notification preferences with Task 7 defaults."""
    from api.services.settings_service import SettingsService

    raw = (
        getattr(settings_record, "notification_preferences", None)
        if settings_record
        else None
    )
    if not isinstance(raw, dict):
        raw = {}

    return {
        "task_reminders_enabled": bool(raw.get("task_reminders_enabled", True)),
        "task_reminder_time": SettingsService._trim_text_value(
            raw.get("task_reminder_time")
        ),
        "morning_digest_enabled": bool(raw.get("morning_digest_enabled", False)),
        "morning_digest_time": SettingsService._trim_text_value(
            raw.get("morning_digest_time")
        ),
        "assistant_reply_notifications_enabled": bool(
            raw.get("assistant_reply_notifications_enabled", False)
        ),
        "assistant_proactive_notifications_enabled": bool(
            raw.get("assistant_proactive_notifications_enabled", False)
        ),
        "schedule_timezone": SettingsService._trim_text_value(
            raw.get("schedule_timezone")
        ),
    }


def clean_notification_preferences(value: Any) -> dict[str, Any]:
    """Validate and normalize notification preference updates."""
    from api.services.settings_service import SettingsService

    if value is None:
        return {}
    if not isinstance(value, dict):
        raise HTTPException(
            status_code=400,
            detail="notification_preferences must be an object",
        )

    SettingsService._reject_unknown_fields(
        value,
        allowed_fields=NOTIFICATION_PREFERENCE_FIELDS,
        scope_name="notification_preferences",
    )

    cleaned: dict[str, Any] = {}
    boolean_fields = (
        "task_reminders_enabled",
        "morning_digest_enabled",
        "assistant_reply_notifications_enabled",
        "assistant_proactive_notifications_enabled",
    )
    for field_name in boolean_fields:
        if field_name in value:
            cleaned[field_name] = SettingsService._clean_bool_field(
                value[field_name],
                f"notification_preferences.{field_name}",
            )

    if "task_reminder_time" in value:
        cleaned["task_reminder_time"] = clean_notification_time(
            value.get("task_reminder_time"),
            "notification_preferences.task_reminder_time",
        )
    if "morning_digest_time" in value:
        cleaned["morning_digest_time"] = clean_notification_time(
            value.get("morning_digest_time"),
            "notification_preferences.morning_digest_time",
        )
    if "schedule_timezone" in value:
        cleaned["schedule_timezone"] = clean_timezone(
            value.get("schedule_timezone"),
            "notification_preferences.schedule_timezone",
        )

    if cleaned.get("task_reminders_enabled") is True:
        if not cleaned.get("task_reminder_time"):
            raise HTTPException(
                status_code=400,
                detail=(
                    "notification_preferences.task_reminders_enabled requires "
                    "task_reminder_time"
                ),
            )
        if not cleaned.get("schedule_timezone"):
            raise HTTPException(
                status_code=400,
                detail=(
                    "notification_preferences.task_reminders_enabled requires "
                    "schedule_timezone"
                ),
            )

    if cleaned.get("morning_digest_enabled") is True:
        if not cleaned.get("morning_digest_time"):
            raise HTTPException(
                status_code=400,
                detail=(
                    "notification_preferences.morning_digest_enabled requires "
                    "morning_digest_time"
                ),
            )
        if not cleaned.get("schedule_timezone"):
            raise HTTPException(
                status_code=400,
                detail=(
                    "notification_preferences.morning_digest_enabled requires "
                    "schedule_timezone"
                ),
            )

    return cleaned
