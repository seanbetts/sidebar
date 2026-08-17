from __future__ import annotations

import logging
from datetime import UTC, date, datetime
from types import SimpleNamespace
from uuid import uuid4

import pytest
from sqlalchemy import text

from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.models.notification_scheduler_heartbeat import NotificationSchedulerHeartbeat
from api.models.task import Task
from api.models.user_settings import UserSettings
from api.services.device_token_service import DeviceTokenService
from api.services.morning_digest_service import MorningDigestService
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_schedule_service import (
    NotificationScheduleService,
    ScheduledNotificationRecipient,
)
from api.services.notification_types import (
    APNSNotificationOutcome,
    NotificationDeliveryResult,
    PushNotificationSendResult,
)
from api.services.push_notification_service import PushNotificationService
from workers import notification_schedule_worker
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


def _simulate_notification_worker_restart() -> None:
    """Discard all process-local scheduler markers between worker invocations."""
    NotificationScheduleService.clear_due_windows()


def test_task_reminders_retry_within_same_window_after_unsuccessful_dispatch(test_db):
    NotificationScheduleService.clear_due_windows()
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


def test_dual_platform_task_reminders_keep_legacy_macos_summary(
    test_db,
    monkeypatch,
):
    NotificationScheduleService.clear_due_windows()
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
    DeviceTokenService.register_token(
        test_db,
        "user-123",
        installation_id="install-macos",
        token="token-macos",
        platform="macos",
        environment="dev",
        capabilities={},
    )
    first_due = _task(
        user_id="user-123",
        title="First due task",
        deadline=date(2026, 1, 15),
    )
    first_due.created_at = datetime(2026, 1, 1, 9, 0, tzinfo=UTC)
    second_due = _task(
        user_id="user-123",
        title="Second due task",
        deadline=date(2026, 1, 15),
    )
    second_due.created_at = datetime(2026, 1, 2, 9, 0, tzinfo=UTC)
    test_db.add_all(
        [
            second_due,
            _task(
                user_id="user-123",
                title="Overdue task",
                deadline=date(2026, 1, 14),
            ),
            first_due,
        ]
    )
    test_db.commit()

    first_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )
    _simulate_notification_worker_restart()
    second_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert first_stats["task_reminders_due"] == 1
    assert second_stats["task_reminders_due"] == 0
    assert first_stats["task_reminders_dispatched"] == 4
    assert second_stats["task_reminders_dispatched"] == 0
    ios_requests = [request for request in captured_requests if request.platform == "ios"]
    macos_requests = [
        request for request in captured_requests if request.platform == "macos"
    ]
    assert len(ios_requests) == 3
    assert [request.payload["aps"]["category"] for request in ios_requests] == [
        "TASK_REMINDER_ACTIONABLE",
        "TASK_REMINDER_ACTIONABLE",
        "TASK_REMINDER_SUMMARY",
    ]
    assert {
        request.payload["aps"]["thread-id"] for request in ios_requests
    } == {"task-reminders"}
    assert ios_requests[0].payload["notification_metadata"]["task_id"] == str(
        first_due.id
    )
    assert ios_requests[0].payload["notification_metadata"]["account_id"] == (
        "user-123"
    )
    assert "task_id" not in ios_requests[0].payload
    assert "account_id" not in ios_requests[0].payload
    assert "account_id" not in ios_requests[2].payload["notification_metadata"]

    assert len(macos_requests) == 1
    macos_payload = macos_requests[0].payload
    assert macos_payload["aps"] == {
        "alert": {
            "title": "2 tasks due today",
            "body": (
                "First due task is due today, plus 1 more due today and 1 overdue."
            ),
        },
        "sound": "default",
        "category": "task_reminder",
    }
    assert macos_payload["notification_metadata"] == {
        "overdue_count": 1,
        "due_today_count": 2,
        "focus_task_id": str(first_due.id),
        "focus_task_title": "First due task",
        "focus_scope": "today",
        "scope": "today",
    }


def test_successful_task_reminder_dispatch_logs_delivered_outcome(caplog):
    with caplog.at_level(logging.INFO, logger="notification_schedule.worker"):
        notification_schedule_worker._log_task_dispatch_outcome(
            user_id="user-123",
            scheduled_time="09:00",
            schedule_timezone="Europe/London",
            decision_reason="delivered",
            detail="intent_count=1 request_count=1 sent_count=1",
        )

    matching_records = [
        record
        for record in caplog.records
        if record.name == "notification_schedule.worker"
        and record.getMessage() == "Scheduled task reminder delivered"
    ]
    assert len(matching_records) == 1
    assert matching_records[0].user_id == "user-123"
    assert matching_records[0].decision_reason == "delivered"


def test_unsuccessful_task_reminder_dispatch_retains_not_delivered_wording(caplog):
    with caplog.at_level(logging.INFO, logger="notification_schedule.worker"):
        notification_schedule_worker._log_task_dispatch_outcome(
            user_id="user-123",
            scheduled_time="09:00",
            schedule_timezone="Europe/London",
            decision_reason="no_reminder_intent",
            detail="no_due_tasks",
        )

    matching_records = [
        record
        for record in caplog.records
        if record.name == "notification_schedule.worker"
        and record.getMessage() == "Scheduled task reminder not delivered"
    ]
    assert len(matching_records) == 1
    assert matching_records[0].decision_reason == "no_reminder_intent"


def test_partially_successful_task_reminder_batch_is_deduped(test_db, monkeypatch):
    NotificationScheduleService.clear_due_windows()
    MorningDigestService.clear_emitted_days()
    delivery_calls = []

    def _partially_deliver(intent, *, device_tokens=None, db=None):
        _ = device_tokens
        _ = db
        delivery_calls.append(intent)
        sent_count = 1 if len(delivery_calls) == 1 else 0
        return NotificationDeliveryResult(
            status="sent",
            request_count=1,
            sent_count=sent_count,
        )

    monkeypatch.setattr(
        NotificationDeliveryService,
        "deliver_intent",
        staticmethod(_partially_deliver),
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
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="First due task",
                deadline=date(2026, 1, 15),
            ),
            _task(
                user_id="user-123",
                title="Second due task",
                deadline=date(2026, 1, 15),
            ),
            _task(
                user_id="user-123",
                title="Overdue task",
                deadline=date(2026, 1, 14),
            ),
        ]
    )
    test_db.commit()

    first_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )
    _simulate_notification_worker_restart()
    second_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert first_stats["task_reminders_due"] == 1
    assert first_stats["task_reminders_dispatched"] == 1
    assert second_stats["task_reminders_due"] == 0
    assert len(delivery_calls) == 3


def test_interrupted_batch_resumes_without_replaying_accepted_intents(
    test_db,
    monkeypatch,
):
    NotificationScheduleService.clear_due_windows()
    MorningDigestService.clear_emitted_days()
    delivery_titles: list[str] = []

    def _interrupt_after_first_acceptance(intent, *, device_tokens=None, db=None):
        _ = device_tokens
        _ = db
        delivery_titles.append(str(intent.title))
        if len(delivery_titles) == 1:
            return NotificationDeliveryResult(
                status="sent",
                request_count=1,
                sent_count=1,
            )
        raise RuntimeError("worker interrupted")

    monkeypatch.setattr(
        NotificationDeliveryService,
        "deliver_intent",
        staticmethod(_interrupt_after_first_acceptance),
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
    first_due = _task(
        user_id="user-123",
        title="First due task",
        deadline=date(2026, 1, 15),
    )
    first_due.created_at = datetime(2026, 1, 1, 9, 0, tzinfo=UTC)
    second_due = _task(
        user_id="user-123",
        title="Second due task",
        deadline=date(2026, 1, 15),
    )
    second_due.created_at = datetime(2026, 1, 2, 9, 0, tzinfo=UTC)
    test_db.add_all(
        [
            second_due,
            first_due,
            _task(
                user_id="user-123",
                title="Overdue task",
                deadline=date(2026, 1, 14),
            ),
        ]
    )
    test_db.commit()

    with pytest.raises(RuntimeError, match="worker interrupted"):
        process_once(
            now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
            digest_dispatcher=lambda db, due_users, *, now=None: 0,
        )

    _simulate_notification_worker_restart()

    def _deliver_remaining(intent, *, device_tokens=None, db=None):
        _ = device_tokens
        _ = db
        delivery_titles.append(str(intent.title))
        return NotificationDeliveryResult(
            status="sent",
            request_count=1,
            sent_count=1,
        )

    monkeypatch.setattr(
        NotificationDeliveryService,
        "deliver_intent",
        staticmethod(_deliver_remaining),
    )

    resumed_stats = process_once(
        now=datetime(2026, 1, 15, 9, 0, 30, tzinfo=UTC),
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert resumed_stats["task_reminders_due"] == 1
    assert resumed_stats["task_reminders_dispatched"] == 2
    assert delivery_titles == [
        "First due task",
        "Second due task",
        "Second due task",
        "1 task overdue",
    ]


def test_zero_success_task_reminder_batch_retries_whole_batch(test_db, monkeypatch):
    NotificationScheduleService.clear_due_windows()
    MorningDigestService.clear_emitted_days()
    delivery_calls = []

    def _skip_delivery(intent, *, device_tokens=None, db=None):
        _ = device_tokens
        _ = db
        delivery_calls.append(intent)
        return NotificationDeliveryResult(
            status="sent",
            request_count=1,
            sent_count=0,
        )

    monkeypatch.setattr(
        NotificationDeliveryService,
        "deliver_intent",
        staticmethod(_skip_delivery),
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
    test_db.add_all(
        [
            _task(
                user_id="user-123",
                title="First due task",
                deadline=date(2026, 1, 15),
            ),
            _task(
                user_id="user-123",
                title="Second due task",
                deadline=date(2026, 1, 15),
            ),
            _task(
                user_id="user-123",
                title="Overdue task",
                deadline=date(2026, 1, 14),
            ),
        ]
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
    assert first_stats["task_reminders_dispatched"] == 0
    assert second_stats["task_reminders_due"] == 1
    assert second_stats["task_reminders_dispatched"] == 0
    assert len(delivery_calls) == 6


def test_scheduled_reminder_dispatch_records_one_audit_row_per_installation(
    test_db,
    monkeypatch,
):
    NotificationScheduleService.clear_due_windows()
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


def test_process_once_enables_notification_worker_scope(monkeypatch):
    observed = {}

    class _FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def commit(self):
            observed["commit_called"] = True

    fake_db = _FakeSession()
    monkeypatch.setattr(notification_schedule_worker, "SessionLocal", lambda: fake_db)
    monkeypatch.setattr(
        notification_schedule_worker,
        "set_notification_worker_scope",
        lambda db, *, enabled: observed.update(scope=(db, enabled)),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationScheduleService,
        "find_due_users",
        lambda db, category, *, now=None: [],
    )

    stats = notification_schedule_worker.process_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        task_dispatcher=lambda db, due_users, *, now=None: 0,
        digest_dispatcher=lambda db, due_users, *, now=None: 0,
    )

    assert observed["scope"] == (fake_db, True)
    assert observed["commit_called"] is True
    assert stats["task_reminders_due"] == 0


def test_execute_once_enables_notification_worker_scope_for_lifecycle_writes(
    monkeypatch,
):
    sessions = []
    events = []

    class _FakeSession:
        def __init__(self):
            self.scope_enabled = False
            sessions.append(self)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def commit(self):
            events.append(("commit", self.scope_enabled))

    def _require_scope(db, event_name, *args, **kwargs):
        _ = args
        _ = kwargs
        assert db.scope_enabled is True
        events.append((event_name, True))

    monkeypatch.setattr(notification_schedule_worker, "SessionLocal", _FakeSession)
    monkeypatch.setattr(
        notification_schedule_worker,
        "set_notification_worker_scope",
        lambda db, *, enabled: setattr(db, "scope_enabled", enabled),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationSchedulerHeartbeatService,
        "mark_started",
        lambda db, *args, **kwargs: _require_scope(
            db,
            "mark_started",
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationSchedulerHeartbeatService,
        "mark_completed",
        lambda db, *args, **kwargs: _require_scope(
            db,
            "mark_completed",
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationSchedulerRunService,
        "record_completed",
        lambda db, *args, **kwargs: _require_scope(
            db,
            "record_completed",
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker,
        "process_once",
        lambda **kwargs: {
            "task_reminders_due": 0,
            "morning_digests_due": 0,
            "task_reminders_dispatched": 0,
            "morning_digests_dispatched": 0,
        },
    )

    notification_schedule_worker.execute_once(
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert [event[0] for event in events] == [
        "mark_started",
        "commit",
        "mark_completed",
        "record_completed",
        "commit",
    ]
    assert len(sessions) == 2


def test_execute_once_enables_notification_worker_scope_for_failure_lifecycle_writes(
    monkeypatch,
):
    events = []

    class _FakeSession:
        def __init__(self):
            self.scope_enabled = False

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def commit(self):
            events.append(("commit", self.scope_enabled))

    def _require_scope(db, event_name, *args, **kwargs):
        _ = args
        _ = kwargs
        assert db.scope_enabled is True
        events.append((event_name, True))

    def _raise_scheduler_error(**kwargs):
        _ = kwargs
        raise RuntimeError("scheduler exploded")

    monkeypatch.setattr(notification_schedule_worker, "SessionLocal", _FakeSession)
    monkeypatch.setattr(
        notification_schedule_worker,
        "set_notification_worker_scope",
        lambda db, *, enabled: setattr(db, "scope_enabled", enabled),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationSchedulerHeartbeatService,
        "mark_started",
        lambda db, *args, **kwargs: _require_scope(
            db,
            "mark_started",
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationSchedulerHeartbeatService,
        "mark_failed",
        lambda db, *args, **kwargs: _require_scope(
            db,
            "mark_failed",
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker.NotificationSchedulerRunService,
        "record_failed",
        lambda db, *args, **kwargs: _require_scope(
            db,
            "record_failed",
            *args,
            **kwargs,
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker,
        "process_once",
        _raise_scheduler_error,
    )

    try:
        notification_schedule_worker.execute_once(
            now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
        )
    except RuntimeError as exc:
        assert str(exc) == "scheduler exploded"
    else:
        raise AssertionError("execute_once should re-raise worker errors")

    assert [event[0] for event in events] == [
        "mark_started",
        "commit",
        "mark_failed",
        "record_failed",
        "commit",
    ]


def test_task_dispatch_uses_user_scoped_sessions(monkeypatch):
    recipient = ScheduledNotificationRecipient(
        user_id="user-123",
        category=notification_schedule_worker.NotificationCategory.TASK_REMINDER,
        scheduled_time="09:00",
        schedule_timezone="Europe/London",
    )
    scoped_db = SimpleNamespace()
    calls: list[tuple[str, object]] = []
    scoped_db.commit = lambda: calls.append(("commit", scoped_db))

    class _ScopedSession:
        def __enter__(self):
            calls.append(("enter_scope", scoped_db))
            return scoped_db

        def __exit__(self, exc_type, exc, tb):
            calls.append(("exit_scope", scoped_db))
            return False

    monkeypatch.setattr(
        notification_schedule_worker,
        "user_scoped_session",
        lambda user_id: _ScopedSession(),
    )
    monkeypatch.setattr(
        notification_schedule_worker.TaskReminderService,
        "inspect_daily_reminder",
        lambda db, *, user_id, schedule_timezone, now=None: (
            calls.append(("inspect", db))
            or SimpleNamespace(intents=(), reason="no_due_tasks")
        ),
    )
    monkeypatch.setattr(
        notification_schedule_worker,
        "_record_dispatch_decision",
        lambda *args, **kwargs: None,
    )
    monkeypatch.setattr(
        notification_schedule_worker.TaskReminderDeliveryStateService,
        "try_acquire_dispatch_lock",
        lambda db, *, user_id, schedule_timezone: True,
    )
    monkeypatch.setattr(
        notification_schedule_worker,
        "_log_task_dispatch_outcome",
        lambda *args, **kwargs: None,
    )

    delivered = notification_schedule_worker._dispatch_task_reminders(
        object(),
        [recipient],
        now=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )

    assert delivered == 0
    assert ("inspect", scoped_db) in calls
