from datetime import UTC, datetime

from api.config import settings
from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.services.notification_scheduler_heartbeat_service import (
    NotificationSchedulerHeartbeatService,
)
from api.services.device_installation_service import DeviceInstallationService
from api.services.notification_diagnostics_audit_service import (
    NotificationDiagnosticsAuditService,
)
from api.services.notification_types import APNSNotificationOutcome, PushNotificationSendResult
from api.services.push_notification_service import PushNotificationService


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def _allow_internal_diagnostics(monkeypatch) -> str:
    user_id = settings.require_test_user_id()
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", user_id)
    return user_id


def test_internal_notification_diagnostics_requires_allowlisted_user(
    test_client,
    monkeypatch,
):
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", "other-user")

    response = test_client.get(
        "/api/internal/notification-diagnostics",
        headers=_auth_headers(),
    )

    assert response.status_code == 403


def test_internal_notification_diagnostics_returns_user_scoped_snapshot(
    test_client,
    test_db,
    monkeypatch,
):
    user_id = _allow_internal_diagnostics(monkeypatch)
    DeviceInstallationService.register_installation(
        test_db,
        user_id,
        installation_id="install-123",
        token="token-12345678",
        platform="ios",
        environment="dev",
    )
    DeviceInstallationService.register_installation(
        test_db,
        "other-user",
        installation_id="install-999",
        token="token-99999999",
        platform="macos",
        environment="dev",
    )
    NotificationDiagnosticsAuditService.record_skip(
        test_db,
        user_id=user_id,
        notification_kind="task_reminder",
        skip_reason="no_target_tokens",
    )
    NotificationDiagnosticsAuditService.record_skip(
        test_db,
        user_id="other-user",
        notification_kind="task_reminder",
        skip_reason="no_target_tokens",
    )
    NotificationSchedulerHeartbeatService.mark_completed(
        test_db,
        started_at=datetime(2026, 4, 20, 8, 0, tzinfo=UTC),
        completed_at=datetime(2026, 4, 20, 8, 0, 1, tzinfo=UTC),
        stats={
            "task_reminders_due": 2,
            "morning_digests_due": 0,
            "task_reminders_dispatched": 2,
            "morning_digests_dispatched": 0,
        },
    )
    test_db.commit()

    response = test_client.get(
        "/api/internal/notification-diagnostics",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["can_access_internal_diagnostics"] is True
    assert body["account_summary"] == {"user_id": user_id}
    assert body["scheduler"]["worker_name"] == "notification_schedule"
    assert body["scheduler"]["last_status"] == "completed"
    assert body["scheduler"]["last_task_reminders_due"] == 2
    assert [row["installation_id"] for row in body["installations"]] == ["install-123"]
    assert [row["user_id"] for row in body["installations"]] == [user_id]
    assert len(body["recent_delivery"]) == 1
    assert body["recent_delivery"][0]["user_id"] == user_id


def test_send_test_push_rejects_installation_owned_by_another_user(
    test_client,
    test_db,
    monkeypatch,
):
    _allow_internal_diagnostics(monkeypatch)
    DeviceInstallationService.register_installation(
        test_db,
        "other-user",
        installation_id="install-999",
        token="token-99999999",
        platform="ios",
        environment="dev",
    )
    test_db.commit()

    response = test_client.post(
        "/api/internal/notification-diagnostics/installations/install-999/test-push",
        headers=_auth_headers(),
    )

    assert response.status_code == 404


def test_send_test_push_writes_audit_row_for_the_target_installation(
    test_client,
    test_db,
    monkeypatch,
):
    user_id = _allow_internal_diagnostics(monkeypatch)
    DeviceInstallationService.register_installation(
        test_db,
        user_id,
        installation_id="install-123",
        token="token-12345678",
        platform="ios",
        environment="dev",
    )
    test_db.commit()

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

    response = test_client.post(
        "/api/internal/notification-diagnostics/installations/install-123/test-push",
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    assert response.json()["installation_id"] == "install-123"
    assert response.json()["accepted"] is True

    test_db.expire_all()
    rows = test_db.query(NotificationDiagnosticsAudit).all()
    assert len(rows) == 1
    assert rows[0].notification_kind == "test_push"
    assert rows[0].installation_id == "install-123"
