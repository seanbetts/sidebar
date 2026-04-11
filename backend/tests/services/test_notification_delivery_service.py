from __future__ import annotations

from types import SimpleNamespace

from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_types import (
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
    PushNotificationSendResult,
)
from api.services.push_notification_service import PushNotificationService


def _token(token: str = "token-123", *, platform: str = "ios") -> SimpleNamespace:
    return SimpleNamespace(token=token, platform=platform)


def test_visible_alerts_build_apns_payloads_with_route_and_category(monkeypatch):
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

    result = NotificationDeliveryService.deliver_intent(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="1 task overdue",
            body="Pay rent is overdue, plus 1 due today.",
            route="sidebar://tasks/today",
            metadata={
                "scope": "today",
                "overdue_count": 1,
                "due_today_count": 1,
                "focus_task_id": "task-123",
                "focus_task_title": "Pay rent",
                "focus_scope": "overdue",
            },
        ),
        device_tokens=[_token()],
    )

    assert result.status == "sent"
    assert result.request_count == 1
    assert len(captured_requests) == 1
    request = captured_requests[0]
    assert request.push_type == "alert"
    assert request.priority == "10"
    assert request.payload["aps"]["alert"] == {
        "title": "1 task overdue",
        "body": "Pay rent is overdue, plus 1 due today.",
    }
    assert request.payload["aps"]["category"] == "task_reminder"
    assert request.payload["sidebar_route"] == "sidebar://tasks/today"
    assert request.payload["notification_category"] == "task_reminder"
    assert request.payload["notification_metadata"] == {
        "scope": "today",
        "overdue_count": 1,
        "due_today_count": 1,
        "focus_task_id": "task-123",
        "focus_task_title": "Pay rent",
        "focus_scope": "overdue",
    }


def test_badge_updates_still_flow_through_transport_layer(monkeypatch):
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

    PushNotificationService.send_badge_update([_token()], badge_count=4)

    assert len(captured_requests) == 1
    request = captured_requests[0]
    assert request.push_type == "background"
    assert request.priority == "5"
    assert request.payload == {
        "aps": {
            "content-available": 1,
            "badge": 4,
        }
    }


def test_unsupported_delivery_modes_return_noop(monkeypatch):
    send_requests_called = False

    def _fake_send_requests(requests):
        nonlocal send_requests_called
        send_requests_called = True
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

    result = NotificationDeliveryService.deliver_intent(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.LIVE_ACTIVITY,
            title="Task reminder",
            body="You have 2 tasks due today.",
            route="sidebar://tasks/today",
        ),
        device_tokens=[_token()],
    )

    assert result.status == "noop"
    assert result.reason == "unsupported_delivery_mode"
    assert send_requests_called is False
