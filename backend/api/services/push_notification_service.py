"""Push notification sender for APNs."""

from __future__ import annotations

import logging
import time
from typing import Any

import httpx
import jwt

from api.config import settings
from api.db.session import SessionLocal
from api.models.device_token import DeviceToken
from api.services.device_token_service import DeviceTokenService
from api.services.notification_types import (
    APNSNotificationRequest,
    PushNotificationSendResult,
)


class PushNotificationService:
    """Send push notifications through APNs."""

    logger = logging.getLogger("notifications.apns")
    _cached_jwt: str | None = None
    _cached_jwt_issued_at: int | None = None

    @classmethod
    def send_badge_update(
        cls, tokens: list[DeviceToken], badge_count: int
    ) -> PushNotificationSendResult:
        """Send a silent badge update to device tokens.

        Args:
            tokens: Device tokens to notify.
            badge_count: Badge count to set.
        """
        requests = [
            APNSNotificationRequest(
                token=token.token,
                platform=token.platform,
                payload={
                    "aps": {
                        "content-available": 1,
                        "badge": badge_count,
                    }
                },
                push_type="background",
                priority="5",
            )
            for token in tokens
        ]
        return cls.send_requests(requests)

    @classmethod
    def send_requests(
        cls,
        requests: list[APNSNotificationRequest],
    ) -> PushNotificationSendResult:
        """Send concrete APNs requests and clean up invalid tokens."""
        if not requests:
            return PushNotificationSendResult(attempted_count=0, sent_count=0)

        auth_token = cls._get_auth_token()
        if not auth_token:
            cls.logger.error(
                "APNs auth unavailable environment=%s attempted_count=%s",
                cls._normalize_environment(settings.apns_env),
                len(requests),
            )
            return PushNotificationSendResult(
                attempted_count=len(requests),
                sent_count=0,
            )

        environment = (settings.apns_env or "dev").lower()
        host = (
            "api.push.apple.com"
            if environment in {"prod", "production"}
            else "api.sandbox.push.apple.com"
        )

        invalid_tokens: list[str] = []
        sent_count = 0
        with httpx.Client(http2=True, timeout=5.0) as client:
            for request in requests:
                topic = request.topic or cls._topic_for_platform(request.platform)
                if not topic:
                    cls.logger.warning(
                        "APNs request skipped category=%s platform=%s "
                        "reason=missing_topic token_suffix=%s",
                        cls._notification_category(request),
                        request.platform,
                        cls._token_suffix(request.token),
                    )
                    continue

                headers = {
                    "authorization": f"bearer {auth_token}",
                    "apns-topic": topic,
                    "apns-push-type": request.push_type,
                    "apns-priority": request.priority,
                }
                url = f"https://{host}/3/device/{request.token}"
                try:
                    response = client.post(url, json=request.payload, headers=headers)
                except httpx.HTTPError as exc:
                    cls.logger.warning(
                        "APNs transport error category=%s platform=%s "
                        "environment=%s topic=%s token_suffix=%s error=%s",
                        cls._notification_category(request),
                        request.platform,
                        cls._normalize_environment(environment),
                        topic,
                        cls._token_suffix(request.token),
                        exc.__class__.__name__,
                    )
                    continue

                if response.status_code >= 400:
                    reason = None
                    try:
                        body = response.json()
                        reason = body.get("reason")
                    except Exception:
                        reason = None
                    cls.logger.warning(
                        "APNs request rejected category=%s platform=%s "
                        "status_code=%s reason=%s token_suffix=%s topic=%s "
                        "environment=%s",
                        cls._notification_category(request),
                        request.platform,
                        response.status_code,
                        reason or "unknown",
                        cls._token_suffix(request.token),
                        topic,
                        cls._normalize_environment(environment),
                    )
                    if response.status_code in {400, 410} and reason in {
                        "BadDeviceToken",
                        "Unregistered",
                        "DeviceTokenNotForTopic",
                    }:
                        invalid_tokens.append(request.token)
                    continue

                cls.logger.info(
                    "APNs request accepted category=%s platform=%s "
                    "status_code=%s topic=%s token_suffix=%s environment=%s",
                    cls._notification_category(request),
                    request.platform,
                    response.status_code,
                    topic,
                    cls._token_suffix(request.token),
                    cls._normalize_environment(environment),
                )
                sent_count += 1

        if invalid_tokens:
            cls._disable_invalid_tokens(invalid_tokens)
        return PushNotificationSendResult(
            attempted_count=len(requests),
            sent_count=sent_count,
            invalid_tokens=tuple(invalid_tokens),
        )

    @classmethod
    def _get_auth_token(cls) -> str | None:
        key_id = settings.apns_key_id
        team_id = settings.apns_team_id
        auth_key = settings.apns_auth_key
        if not (key_id and team_id and auth_key):
            return None

        now = int(time.time())
        if (
            cls._cached_jwt
            and cls._cached_jwt_issued_at
            and now - cls._cached_jwt_issued_at < 50 * 60
        ):
            return cls._cached_jwt

        private_key = auth_key.replace("\\n", "\n")
        payload: dict[str, Any] = {"iss": team_id, "iat": now}
        headers = {"kid": key_id}
        token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
        cls._cached_jwt = token
        cls._cached_jwt_issued_at = now
        return token

    @classmethod
    def _topic_for_platform(cls, platform: str) -> str | None:
        if platform == "ios":
            return settings.apns_topic_ios or settings.apns_topic
        if platform == "macos":
            return settings.apns_topic_macos or settings.apns_topic
        return settings.apns_topic

    @staticmethod
    def _disable_invalid_tokens(tokens: list[str]) -> None:
        with SessionLocal() as db:
            DeviceTokenService.disable_tokens_by_value(db, tokens)
            db.commit()

    @staticmethod
    def _token_suffix(token: str) -> str:
        """Return the last visible portion of a device token for logs."""
        return str(token or "")[-8:]

    @staticmethod
    def _notification_category(request: APNSNotificationRequest) -> str:
        """Extract a stable notification category value for diagnostics."""
        category = request.payload.get("notification_category")
        return str(category or "unknown")

    @staticmethod
    def _normalize_environment(environment: str | None) -> str:
        """Normalize environment labels for consistent logging."""
        return str(environment or "dev").lower()
