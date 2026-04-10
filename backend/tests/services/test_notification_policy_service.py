from __future__ import annotations

from types import SimpleNamespace

from api.services.notification_policy_service import NotificationPolicyService
from api.services.notification_types import (
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
)


def _settings(notification_preferences: dict | None = None) -> SimpleNamespace:
    return SimpleNamespace(notification_preferences=notification_preferences)


def _token(
    *,
    is_foreground: bool = False,
    capabilities: dict[str, bool] | None = None,
) -> SimpleNamespace:
    return SimpleNamespace(
        is_foreground=is_foreground,
        capabilities=capabilities or {},
    )


def test_task_reminders_blocked_until_schedule_is_fully_configured():
    decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Task reminder",
            body="You have tasks due today.",
            route="sidebar://tasks/today",
        ),
        settings_record=_settings(),
        device_tokens=[_token()],
    )

    assert decision.should_deliver is False
    assert decision.reason == "schedule_incomplete"


def test_morning_digest_requires_explicit_enablement_and_schedule():
    default_decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.MORNING_DIGEST,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Morning digest",
            body="Your day at a glance.",
            route="sidebar://digest/morning",
        ),
        settings_record=_settings(),
        device_tokens=[_token()],
    )

    configured_without_time = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.MORNING_DIGEST,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Morning digest",
            body="Your day at a glance.",
            route="sidebar://digest/morning",
        ),
        settings_record=_settings(
            {
                "morning_digest_enabled": True,
                "schedule_timezone": "Europe/London",
            }
        ),
        device_tokens=[_token()],
    )

    assert default_decision.should_deliver is False
    assert default_decision.reason == "disabled"
    assert configured_without_time.should_deliver is False
    assert configured_without_time.reason == "schedule_incomplete"


def test_assistant_reply_notifications_blocked_by_default():
    decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.ASSISTANT_REPLY,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="sideBar replied",
            body="Your assistant has responded.",
            route="sidebar://chat/conversation-123",
        ),
        settings_record=_settings(),
        device_tokens=[_token()],
    )

    assert decision.should_deliver is False
    assert decision.reason == "disabled"


def test_proactive_notifications_blocked_by_default():
    decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.ASSISTANT_PROACTIVE,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="sideBar update",
            body="A proactive update is ready.",
            route="sidebar://chat/conversation-123",
        ),
        settings_record=_settings(),
        device_tokens=[_token()],
    )

    assert decision.should_deliver is False
    assert decision.reason == "disabled"


def test_assistant_reply_notifications_require_user_to_be_away():
    active_device_decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.ASSISTANT_REPLY,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="sideBar replied",
            body="Your assistant has responded.",
            route="sidebar://chat/conversation-123",
        ),
        settings_record=_settings(
            {
                "assistant_reply_notifications_enabled": True,
            }
        ),
        device_tokens=[_token(is_foreground=True)],
    )

    away_decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.ASSISTANT_REPLY,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="sideBar replied",
            body="Your assistant has responded.",
            route="sidebar://chat/conversation-123",
        ),
        settings_record=_settings(
            {
                "assistant_reply_notifications_enabled": True,
            }
        ),
        device_tokens=[_token(is_foreground=False)],
    )

    assert active_device_decision.should_deliver is False
    assert active_device_decision.reason == "user_present"
    assert away_decision.should_deliver is True
    assert away_decision.reason is None


def test_required_capabilities_filter_delivery_tokens():
    decision = NotificationPolicyService.evaluate(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Task reminder",
            body="You have tasks due today.",
            route="sidebar://tasks/today",
            required_capabilities=("supports_live_activities",),
        ),
        settings_record=_settings(
            {
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            }
        ),
        device_tokens=[
            _token(capabilities={"supports_live_activities": False}),
            _token(capabilities={"supports_live_activities": True}),
        ],
    )

    assert decision.should_deliver is True
    assert len(decision.matched_tokens) == 1
