from __future__ import annotations

from datetime import UTC, date, datetime
from uuid import uuid4

from api.models.device_token import DeviceToken
from api.models.task import Task
from api.models.user_settings import UserSettings
from api.services.morning_digest_service import MorningDigestService
from api.services.notification_types import PushNotificationSendResult
from api.services.push_notification_service import PushNotificationService
from workers.notification_schedule_worker import process_once


def _task(
    *,
    user_id: str,
    title: str,
    deadline: date | None,
    status: str = "active",
) -> Task:
    return Task(
        id=uuid4(),
        user_id=user_id,
        title=title,
        status=status,
        deadline=deadline,
    )


def test_morning_digest_builds_short_task_snapshot_with_dedicated_route(test_db):
    MorningDigestService.clear_emitted_days()
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="Overdue item",
                deadline=date(2026, 1, 14),
            ),
            _task(
                user_id="user-123",
                title="Due today item",
                deadline=date(2026, 1, 15),
            ),
            _task(
                user_id="user-123",
                title="Focus next",
                deadline=None,
            ),
        ]
    )
    test_db.commit()

    digest = MorningDigestService.build_digest(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 8, 30, tzinfo=UTC),
    )

    assert digest is not None
    assert digest.title == "Morning digest"
    assert digest.body == "1 overdue, 1 due today, 3 active tasks."
    assert len(digest.body) <= 60
    assert digest.route == "sidebar://digest/morning"
    assert digest.metadata == {
        "overdue_count": 1,
        "due_today_count": 1,
        "active_task_count": 3,
        "focus_title": "Overdue item",
        "scope": "morning_digest",
    }


def test_morning_digest_noops_when_nothing_worth_surfacing(test_db):
    MorningDigestService.clear_emitted_days()
    test_db.add(
        _task(
            user_id="user-123",
            title="Finished item",
            deadline=date(2026, 1, 15),
            status="completed",
        )
    )
    test_db.commit()

    digest = MorningDigestService.build_digest(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        now=datetime(2026, 1, 15, 8, 30, tzinfo=UTC),
    )

    assert digest is None


def test_morning_digest_dispatches_for_due_users_via_scheduled_worker(
    test_db,
    monkeypatch,
):
    MorningDigestService.clear_emitted_days()
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

    test_db.add(
        UserSettings(
            user_id="user-123",
            notification_preferences={
                "morning_digest_enabled": True,
                "morning_digest_time": "08:30",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.add(
        DeviceToken(
            user_id="user-123",
            token="token-123",
            platform="ios",
            environment="dev",
            capabilities={},
            is_foreground=False,
            last_seen_at=None,
        )
    )
    test_db.add(
        _task(
            user_id="user-123",
            title="Focus next",
            deadline=None,
        )
    )
    test_db.commit()

    stats = process_once(now=datetime(2026, 1, 15, 8, 30, tzinfo=UTC))

    assert stats["morning_digests_due"] == 1
    assert stats["morning_digests_dispatched"] == 1
    assert len(captured_requests) == 1
    assert captured_requests[0].payload["notification_category"] == "morning_digest"
    assert captured_requests[0].payload["sidebar_route"] == "sidebar://digest/morning"
