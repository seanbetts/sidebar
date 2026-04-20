from __future__ import annotations

import logging
from datetime import UTC, date, datetime
from uuid import uuid4

from sqlalchemy import text

from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.models.notification_scheduler_heartbeat import NotificationSchedulerHeartbeat
from api.models.task import Task
from api.models.user_settings import UserSettings
from api.services.device_token_service import DeviceTokenService
from api.services.morning_digest_service import MorningDigestService
from api.services.notification_schedule_service import NotificationScheduleService
from api.services.notification_types import (
    APNSNotificationOutcome,
    PushNotificationSendResult,
)
from api.services.push_notification_service import PushNotificationService
from api.services.task_reminder_service import TaskReminderService
from workers.notification_schedule_worker import execute_once, process_once


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


def test_task_reminders_retry_within_same_window_after_unsuccessful_dispatch(test_db):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()
    test_db.add(
        UserSettings(
            user_id="user-123",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    dispatched_counts: list[int] = []

    def _failed_task_dispatcher(db, due_users, *, now=None):
        _ = db
        _ = now
        dispatched_counts.append(len(due_users))
        return 0

    first_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        task_dispatcher=_failed_task_dispatcher,
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )
    second_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        task_dispatcher=_failed_task_dispatcher,
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert first_stats["task_reminders_due"] == 1
    assert second_stats["task_reminders_due"] == 1
    assert dispatched_counts == [1, 1]


def test_successful_task_reminders_are_deduped_within_same_window(
    test_db,
    monkeypatch,
):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
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
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-123",
        token="token-123",
        platform="ios",
        environment="dev",
        capabilities={},
    )
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    first_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )
    second_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert first_stats["task_reminders_due"] == 1
    assert second_stats["task_reminders_due"] == 0
    assert first_stats["task_reminders_dispatched"] == 1
    assert second_stats["task_reminders_dispatched"] == 0
    assert len(captured_requests) == 1


def test_scheduled_reminder_dispatch_records_one_audit_row_per_installation(
    test_db,
    monkeypatch,
):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()

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
    test_db.add(
        UserSettings(
            user_id="user-123",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-123",
        token="token-123",
        platform="ios",
        environment="dev",
        capabilities={},
    )
    DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-456",
        token="token-456",
        platform="macos",
        environment="dev",
        capabilities={},
    )
    test_db.add(
        _task(
            user_id="user-123",
            title="Pay rent",
            deadline=date(2026, 1, 15),
        )
    )
    test_db.commit()

    process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    rows = test_db.query(NotificationDiagnosticsAudit).all()
    assert len(rows) == 2
    assert {row.installation_id for row in rows} == {"install-123", "install-456"}


def test_execute_once_persists_scheduler_heartbeat_on_success(test_db):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()

    stats = execute_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        task_dispatcher=lambda db, due_users, *, now=None: 0,
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    heartbeat = test_db.get(
        NotificationSchedulerHeartbeat,
        "notification_schedule",
    )
    assert stats == {
        "task_reminders_due": 0,
        "morning_digests_due": 0,
        "task_reminders_dispatched": 0,
        "morning_digests_dispatched": 0,
    }
    assert heartbeat is not None
    assert heartbeat.last_status == "completed"
    assert heartbeat.last_started_at == datetime(2026, 1, 15, 9, 0, tzinfo=UTC)
    assert heartbeat.last_task_reminders_due == 0
    assert heartbeat.last_task_reminders_dispatched == 0
    history_rows = test_db.execute(
        text(
            """
            select status, task_reminders_due, task_reminders_dispatched
            from notification_scheduler_runs
            order by started_at desc
            """
        )
    ).all()
    assert history_rows == [("completed", 0, 0)]


def test_execute_once_persists_scheduler_heartbeat_on_failure(test_db):
    def _boom(db, due_users, *, now=None):
        _ = db
        _ = due_users
        _ = now
        raise RuntimeError("scheduler exploded")

    try:
        execute_once(
            now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
            task_dispatcher=_boom,
            digest_dispatcher=lambda db, due_users, *, now=None: 0,
        )
    except RuntimeError as exc:
        assert str(exc) == "scheduler exploded"
    else:
        raise AssertionError("execute_once should re-raise worker errors")

    heartbeat = test_db.get(
        NotificationSchedulerHeartbeat,
        "notification_schedule",
    )
    assert heartbeat is not None
    assert heartbeat.last_status == "failed"
    assert heartbeat.last_started_at == datetime(2026, 1, 15, 9, 0, tzinfo=UTC)
    assert heartbeat.last_error == "scheduler exploded"


def test_no_reminder_intent_is_logged_for_internal_diagnostics_users(test_db, monkeypatch):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", "user-123")
    test_db.add(
        UserSettings(
            user_id="user-123",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.commit()

    stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    decision_rows = test_db.execute(
        text(
            """
            select user_id, decision_stage, decision_reason, detail
            from notification_scheduler_decisions
            order by created_at asc
            """
        )
    ).all()

    assert stats["task_reminders_due"] == 1
    assert stats["task_reminders_dispatched"] == 0
    assert ("user-123", "dispatch", "no_reminder_intent", "no_due_tasks") in decision_rows


def test_due_task_reminder_non_delivery_is_logged_for_worker_ops(test_db, caplog):
    NotificationScheduleService.clear_due_windows()
    TaskReminderService.clear_emitted_days()
    MorningDigestService.clear_emitted_days()
    test_db.add(
        UserSettings(
            user_id="user-ops-log",
            notification_preferences={
                "task_reminders_enabled": True,
                "task_reminder_time": "09:00",
                "schedule_timezone": "Europe/London",
            },
        )
    )
    test_db.commit()

    with caplog.at_level(logging.INFO, logger="notification_schedule.worker"):
        stats = process_once(
            now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
            digest_dispatcher=lambda db, due_users, *, now=None: 0,
        )

    assert stats["task_reminders_due"] == 1
    assert stats["task_reminders_dispatched"] == 0
    matching_records = [
        record
        for record in caplog.records
        if record.name == "notification_schedule.worker"
        and record.getMessage() == "Scheduled task reminder not delivered"
    ]
    assert len(matching_records) == 1
    assert matching_records[0].user_id == "user-ops-log"
    assert matching_records[0].decision_reason == "no_reminder_intent"
    assert matching_records[0].detail == "no_due_tasks"
