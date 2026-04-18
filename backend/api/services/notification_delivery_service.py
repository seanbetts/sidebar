"""Notification delivery orchestration for APNs-backed notifications."""

from __future__ import annotations

import logging
from typing import Any

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
    def deliver_intent(
        intent: NotificationIntent,
        *,
        device_tokens: list[Any] | tuple[Any, ...] | None = None,
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
        return NotificationDeliveryResult(
            status="sent",
            request_count=len(requests),
            sent_count=result.sent_count,
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
                    payload={
                        "aps": {
                            "alert": {
                                "title": intent.title or "",
                                "body": intent.body or "",
                            },
                            "sound": "default",
                            "category": intent.category.value,
                        },
                        "sidebar_route": intent.route,
                        "notification_category": intent.category.value,
                        "notification_metadata": intent.metadata,
                    },
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
                )
                for token in tokens
            ]

        return None
