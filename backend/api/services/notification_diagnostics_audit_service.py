"""Write-side service for durable notification diagnostics audit rows."""

from __future__ import annotations

from collections.abc import Iterable

from sqlalchemy.orm import Session

from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.services.notification_types import APNSNotificationOutcome


class NotificationDiagnosticsAuditService:
    """Persist durable rows for notification diagnostics."""

    @staticmethod
    def record_skip(
        db: Session,
        *,
        user_id: str,
        notification_kind: str,
        skip_reason: str,
        installation_id: str | None = None,
        platform: str | None = None,
        token: str | None = None,
        apns_topic: str | None = None,
        apns_env: str | None = None,
    ) -> None:
        """Persist one skipped notification audit row."""
        db.add(
            NotificationDiagnosticsAudit(
                user_id=user_id,
                notification_kind=notification_kind,
                installation_id=installation_id,
                platform=platform,
                token_suffix=NotificationDiagnosticsAuditService._token_suffix(token),
                apns_topic=apns_topic,
                apns_env=apns_env,
                delivery_result="skipped",
                skip_reason=skip_reason,
                apns_status_code=None,
                apns_reason=None,
            )
        )
        db.flush()

    @staticmethod
    def record_transport_outcomes(
        db: Session,
        *,
        user_id: str,
        notification_kind: str,
        outcomes: Iterable[APNSNotificationOutcome],
    ) -> None:
        """Persist one row per APNs request outcome."""
        for outcome in outcomes:
            db.add(
                NotificationDiagnosticsAudit(
                    user_id=user_id,
                    notification_kind=notification_kind,
                    installation_id=outcome.installation_id,
                    platform=outcome.platform,
                    token_suffix=NotificationDiagnosticsAuditService._token_suffix(
                        outcome.token
                    ),
                    apns_topic=outcome.topic,
                    apns_env=outcome.environment,
                    delivery_result="sent" if outcome.accepted else "failed",
                    skip_reason=None,
                    apns_status_code=outcome.status_code,
                    apns_reason=outcome.reason,
                )
            )
        db.flush()

    @staticmethod
    def _token_suffix(token: str | None) -> str | None:
        """Return the visible token suffix for diagnostics."""
        normalized_token = str(token or "").strip()
        if not normalized_token:
            return None
        return normalized_token[-8:]
