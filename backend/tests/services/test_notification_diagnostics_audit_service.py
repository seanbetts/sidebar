from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.services.notification_diagnostics_audit_service import (
    NotificationDiagnosticsAuditService,
)
from api.services.notification_types import APNSNotificationOutcome


def test_record_skip_persists_notification_diagnostics_audit_row(test_db):
    NotificationDiagnosticsAuditService.record_skip(
        test_db,
        user_id="user-123",
        notification_kind="task_reminder",
        skip_reason="no_target_tokens",
    )
    test_db.commit()

    row = test_db.query(NotificationDiagnosticsAudit).one()
    assert row.user_id == "user-123"
    assert row.notification_kind == "task_reminder"
    assert row.delivery_result == "skipped"
    assert row.skip_reason == "no_target_tokens"


def test_record_transport_outcomes_persists_apns_details(test_db):
    NotificationDiagnosticsAuditService.record_transport_outcomes(
        test_db,
        user_id="user-123",
        notification_kind="task_reminder",
        outcomes=[
            APNSNotificationOutcome(
                token="token-12345678",
                installation_id="install-123",
                platform="ios",
                topic="ai.sidebar.sidebar",
                environment="dev",
                status_code=400,
                reason="BadDeviceToken",
                accepted=False,
            ),
            APNSNotificationOutcome(
                token="token-abcdefgh",
                installation_id="install-456",
                platform="macos",
                topic="ai.sidebar.sidebar.macos",
                environment="prod",
                status_code=200,
                reason=None,
                accepted=True,
            ),
        ],
    )
    test_db.commit()

    rows = (
        test_db.query(NotificationDiagnosticsAudit)
        .order_by(NotificationDiagnosticsAudit.installation_id.asc())
        .all()
    )

    assert [row.installation_id for row in rows] == ["install-123", "install-456"]
    assert rows[0].delivery_result == "failed"
    assert rows[0].apns_status_code == 400
    assert rows[0].apns_reason == "BadDeviceToken"
    assert rows[0].token_suffix == "12345678"
    assert rows[1].delivery_result == "sent"
    assert rows[1].apns_topic == "ai.sidebar.sidebar.macos"
    assert rows[1].apns_env == "prod"
