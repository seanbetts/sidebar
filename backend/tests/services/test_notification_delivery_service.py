from __future__ import annotations

import logging
from types import SimpleNamespace

from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_types import (
    APNSNotificationOutcome,
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
    PushNotificationSendResult,
)
from api.services.push_notification_service import PushNotificationService


def _token(token: str = "token-123", *, platform: str = "ios") -> SimpleNamespace:
    return SimpleNamespace(
        token=token,
        platform=platform,
        installation_id=f"install-{token}",
    )


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
            title="1 task due today",
            body="Quarterly review is due today, plus 1 overdue.",
            route="sidebar://tasks/today",
            metadata={
                "scope": "today",
                "overdue_count": 1,
                "due_today_count": 1,
                "focus_task_id": "task-123",
                "focus_task_title": "Quarterly review",
                "focus_scope": "today",
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
        "title": "1 task due today",
        "body": "Quarterly review is due today, plus 1 overdue.",
    }
    assert request.payload["aps"]["category"] == "task_reminder"
    assert request.payload["sidebar_route"] == "sidebar://tasks/today"
    assert request.payload["notification_category"] == "task_reminder"
    assert request.payload["notification_metadata"] == {
        "scope": "today",
        "overdue_count": 1,
        "due_today_count": 1,
        "focus_task_id": "task-123",
        "focus_task_title": "Quarterly review",
        "focus_scope": "today",
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


def test_no_target_tokens_logs_delivery_skip(caplog):
    caplog.set_level(logging.INFO, logger="notifications.delivery")

    result = NotificationDeliveryService.deliver_intent(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Task reminder",
            body="You have 2 tasks due today.",
            route="sidebar://tasks/today",
        ),
        device_tokens=[],
    )

    assert result.status == "noop"
    assert result.reason == "no_target_tokens"
    assert (
        "Notification delivery skipped category=task_reminder user_id=user-123 "
        "reason=no_target_tokens"
    ) in caplog.text


def test_no_target_tokens_create_skipped_audit_row(test_db):
    NotificationDeliveryService.deliver_intent(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Task reminder",
            body="You have 2 tasks due today.",
            route="sidebar://tasks/today",
        ),
        device_tokens=[],
        db=test_db,
    )
    test_db.commit()

    row = test_db.query(NotificationDiagnosticsAudit).one()
    assert row.user_id == "user-123"
    assert row.notification_kind == "task_reminder"
    assert row.delivery_result == "skipped"
    assert row.skip_reason == "no_target_tokens"


def test_successful_alert_delivery_creates_sent_audit_rows(test_db, monkeypatch):
    def _fake_send_requests(requests):
        return PushNotificationSendResult(
            attempted_count=len(requests),
            sent_count=len(requests),
            invalid_tokens=(),
            outcomes=tuple(
                APNSNotificationOutcome(
                    token=request.token,
                    installation_id=request.installation_id,
                    platform=request.platform,
                    topic="ai.sidebar.sidebar",
                    environment="dev",
                    status_code=200,
                    reason=None,
                    accepted=True,
                )
                for request in requests
            ),
        )

    monkeypatch.setattr(
        PushNotificationService,
        "send_requests",
        staticmethod(_fake_send_requests),
    )

    NotificationDeliveryService.deliver_intent(
        NotificationIntent(
            user_id="user-123",
            category=NotificationCategory.TASK_REMINDER,
            delivery_mode=NotificationDeliveryMode.ALERT,
            title="Task reminder",
            body="You have 2 tasks due today.",
            route="sidebar://tasks/today",
        ),
        device_tokens=[_token("token-123")],
        db=test_db,
    )
    test_db.commit()

    row = test_db.query(NotificationDiagnosticsAudit).one()
    assert row.installation_id == "install-token-123"
    assert row.delivery_result == "sent"
    assert row.apns_topic == "ai.sidebar.sidebar"
    assert row.apns_env == "dev"
