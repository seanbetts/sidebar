from __future__ import annotations

import logging

import httpx

from api.services.notification_types import APNSNotificationRequest
from api.services.push_notification_service import PushNotificationService


class _FakeResponse:
    def __init__(self, *, status_code: int, reason: str | None = None):
        self.status_code = status_code
        self._reason = reason

    def json(self):
        if self._reason is None:
            return {}
        return {"reason": self._reason}


class _FakeClient:
    def __init__(self, responses):
        self._responses = iter(responses)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def post(self, url, json, headers):
        _ = (url, json, headers)
        return next(self._responses)


def test_send_requests_logs_apns_rejection(monkeypatch, caplog):
    caplog.set_level(logging.WARNING, logger="notifications.apns")

    monkeypatch.setattr(
        PushNotificationService,
        "_get_auth_token",
        classmethod(lambda cls: "auth-token"),
    )
    monkeypatch.setattr(
        PushNotificationService,
        "_topic_for_platform",
        classmethod(lambda cls, platform: "ai.sidebar.sidebar"),
    )
    monkeypatch.setattr(
        PushNotificationService,
        "_disable_invalid_tokens",
        staticmethod(lambda tokens: None),
    )
    monkeypatch.setattr(
        httpx,
        "Client",
        lambda **kwargs: _FakeClient(
            [_FakeResponse(status_code=410, reason="Unregistered")]
        ),
    )

    PushNotificationService.send_requests(
        [
            APNSNotificationRequest(
                token="abc1234567890",
                platform="ios",
                payload={
                    "aps": {"alert": {"title": "Title", "body": "Body"}},
                    "notification_category": "task_reminder",
                },
                push_type="alert",
                priority="10",
            )
        ]
    )

    assert (
        "APNs request rejected category=task_reminder platform=ios "
        "status_code=410 reason=Unregistered token_suffix=34567890"
    ) in caplog.text


def test_send_requests_logs_apns_acceptance(monkeypatch, caplog):
    caplog.set_level(logging.INFO, logger="notifications.apns")

    monkeypatch.setattr(
        PushNotificationService,
        "_get_auth_token",
        classmethod(lambda cls: "auth-token"),
    )
    monkeypatch.setattr(
        PushNotificationService,
        "_topic_for_platform",
        classmethod(lambda cls, platform: "ai.sidebar.sidebar"),
    )
    monkeypatch.setattr(
        httpx,
        "Client",
        lambda **kwargs: _FakeClient([_FakeResponse(status_code=200)]),
    )

    PushNotificationService.send_requests(
        [
            APNSNotificationRequest(
                token="abc1234567890",
                platform="macos",
                payload={
                    "aps": {"alert": {"title": "Title", "body": "Body"}},
                    "notification_category": "task_reminder",
                },
                push_type="alert",
                priority="10",
                topic="ai.sidebar.sidebar",
            )
        ]
    )

    assert (
        "APNs request accepted category=task_reminder platform=macos "
        "status_code=200 topic=ai.sidebar.sidebar token_suffix=34567890"
    ) in caplog.text
