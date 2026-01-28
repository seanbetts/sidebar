"""Push notification sender for APNs."""

from __future__ import annotations

import time
from typing import Any

import httpx
import jwt

from api.config import settings
from api.models.device_token import DeviceToken


class PushNotificationService:
    """Send push notifications through APNs."""

    _cached_jwt: str | None = None
    _cached_jwt_issued_at: int | None = None

    @classmethod
    def send_badge_update(cls, tokens: list[DeviceToken], badge_count: int) -> None:
        """Send a silent badge update to device tokens.

        Args:
            tokens: Device tokens to notify.
            badge_count: Badge count to set.
        """
        if not tokens:
            return

        auth_token = cls._get_auth_token()
        if not auth_token:
            return

        environment = (settings.apns_env or "dev").lower()
        host = (
            "api.push.apple.com"
            if environment in {"prod", "production"}
            else "api.sandbox.push.apple.com"
        )

        with httpx.Client(http2=True, timeout=5.0) as client:
            for token in tokens:
                topic = cls._topic_for_token(token)
                if not topic:
                    continue

                headers = {
                    "authorization": f"bearer {auth_token}",
                    "apns-topic": topic,
                    "apns-push-type": "background",
                    "apns-priority": "5",
                }
                payload = {
                    "aps": {
                        "content-available": 1,
                        "badge": badge_count,
                    }
                }
                url = f"https://{host}/3/device/{token.token}"
                try:
                    response = client.post(url, json=payload, headers=headers)
                    if response.status_code >= 400:
                        continue
                except httpx.HTTPError:
                    continue

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
    def _topic_for_token(cls, token: DeviceToken) -> str | None:
        if token.platform == "ios":
            return settings.apns_topic_ios or settings.apns_topic
        if token.platform == "macos":
            return settings.apns_topic_macos or settings.apns_topic
        return settings.apns_topic
