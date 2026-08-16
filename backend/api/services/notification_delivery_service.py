"""Notification delivery orchestration for APNs-backed notifications."""

from __future__ import annotations

import logging
from typing import Any

from sqlalchemy.orm import Session

from api.services.notification_diagnostics_audit_service import (
    NotificationDiagnosticsAuditService,
)
from api.services.notification_types import (
    APNSNotificationRequest,
    NotificationDeliveryMode,
    NotificationDeliveryResult,
    NotificationIntent,
)
from api.services.push_notification_service import PushNotificationService

logger = logging.getLogger("notifications.delivery")


class NotificationDeliveryService:
    """Convert approved intents into transport requests."""

    @staticmethod
    def _build_alert_payload(intent: NotificationIntent) -> dict[str, Any]:
        """Build one APNs alert payload from a transport-neutral intent."""
        aps: dict[str, Any] = {
            "alert": {
                "title": intent.title or "",
                "body": intent.body or "",
            },
            "sound": "default",
            "category": intent.native_category or intent.category.value,
        }
        if intent.thread_id:
            aps["thread-id"] = intent.thread_id
        return {
            "aps": aps,
            "sidebar_route": intent.route,
            "notification_category": intent.category.value,
            "notification_metadata": intent.metadata,
        }

    @staticmethod
    def deliver_intent(
        intent: NotificationIntent,
        *,
        device_tokens: list[Any] | tuple[Any, ...] | None = None,
        db: Session | None = None,
    ) -> NotificationDeliveryResult:
        """Deliver one notification intent to the provided device tokens."""
        requests = NotificationDeliveryService.build_requests(
            intent,
            device_tokens=device_tokens,
        )
        if requests is None:
            logger.info(
                "Notification delivery skipped category=%s user_id=%s "
                "reason=unsupported_delivery_mode",
                intent.category.value,
                intent.user_id,
            )
            if db is not None:
                NotificationDiagnosticsAuditService.record_skip(
                    db,
                    user_id=intent.user_id,
                    notification_kind=intent.category.value,
                    skip_reason="unsupported_delivery_mode",
                )
            return NotificationDeliveryResult(
                status="noop",
                request_count=0,
                sent_count=0,
                reason="unsupported_delivery_mode",
            )
        if not requests:
            logger.info(
                "Notification delivery skipped category=%s user_id=%s "
                "reason=no_target_tokens",
                intent.category.value,
                intent.user_id,
            )
            if db is not None:
                NotificationDiagnosticsAuditService.record_skip(
                    db,
                    user_id=intent.user_id,
                    notification_kind=intent.category.value,
                    skip_reason="no_target_tokens",
                )
            return NotificationDeliveryResult(
                status="noop",
                request_count=0,
                sent_count=0,
                reason="no_target_tokens",
            )

        result = PushNotificationService.send_requests(requests)
        logger.info(
            "Notification delivery attempted category=%s user_id=%s "
            "request_count=%s sent_count=%s",
            intent.category.value,
            intent.user_id,
            len(requests),
            result.sent_count,
        )
        if db is not None and result.outcomes:
            NotificationDiagnosticsAuditService.record_transport_outcomes(
                db,
                user_id=intent.user_id,
                notification_kind=intent.category.value,
                outcomes=result.outcomes,
            )
        return NotificationDeliveryResult(
            status="sent",
            request_count=len(requests),
            sent_count=result.sent_count,
            outcomes=result.outcomes,
        )

    @staticmethod
    def build_requests(
        intent: NotificationIntent,
        *,
        device_tokens: list[Any] | tuple[Any, ...] | None = None,
    ) -> list[APNSNotificationRequest] | None:
        """Build APNs requests for supported notification delivery modes."""
        tokens = device_tokens or ()
        if intent.delivery_mode == NotificationDeliveryMode.ALERT:
            return [
                APNSNotificationRequest(
                    token=str(token.token),
                    platform=str(token.platform),
                    push_type="alert",
                    priority="10",
                    payload=NotificationDeliveryService._build_alert_payload(intent),
                    installation_id=getattr(token, "installation_id", None),
                )
                for token in tokens
            ]

        if intent.delivery_mode == NotificationDeliveryMode.BADGE:
            if intent.badge_count is None:
                return []
            return [
                APNSNotificationRequest(
                    token=str(token.token),
                    platform=str(token.platform),
                    push_type="background",
                    priority="5",
                    payload={
                        "aps": {
                            "content-available": 1,
                            "badge": intent.badge_count,
                        }
                    },
                    installation_id=getattr(token, "installation_id", None),
                )
                for token in tokens
            ]

        return None
