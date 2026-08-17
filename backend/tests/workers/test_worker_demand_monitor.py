"""Tests for supervised demand-driven Fly worker control."""

from __future__ import annotations

import logging
from dataclasses import FrozenInstanceError
from datetime import date, datetime, timezone
from typing import NoReturn

import pytest
from pydantic import SecretStr

from api.config import Settings
from api.services.fly_machine_service import (
    FlyMachineTransientError,
    MachineStartResult,
    MachineStartStatus,
)
from api.services.worker_queue_demand_service import (
    WorkerQueueDemand,
    WorkerQueueDemandService,
)
from workers import worker_demand_monitor


class StopLoop(BaseException):
    """Terminate an otherwise infinite worker loop without being caught."""


class OpaqueSecretStr(SecretStr):
    """Fail if code outside the lifecycle service unwraps this test secret."""

    def get_secret_value(self) -> str:
        """Reject raw access by the worker-demand monitor."""
        raise AssertionError("worker monitor attempted to unwrap Fly token")


class FakeSession:
    """Record lifecycle calls made by one demand inspection cycle."""

    def __init__(self) -> None:
        self.rolled_back = False
        self.closed = False

    def __enter__(self) -> FakeSession:
        """Return this session from the context manager."""
        return self

    def __exit__(self, exc_type: object, exc: object, tb: object) -> bool:
        """Record context-managed close without swallowing exceptions."""
        self.closed = True
        return False

    def rollback(self) -> None:
        """Record transaction cleanup."""
        self.rolled_back = True


class FakeFlyMachineService:
    """Return deterministic starts while recording controlled process groups."""

    def __init__(self, *, failing_group: str | None = None) -> None:
        self.failing_group = failing_group
        self.started_groups: list[str] = []

    def ensure_started(self, process_group: str) -> MachineStartResult:
        """Return a start result unless this process group is configured to fail."""
        self.started_groups.append(process_group)
        if process_group == self.failing_group:
            raise FlyMachineTransientError("sensitive provider detail")
        return MachineStartResult(
            process_group=process_group,  # type: ignore[arg-type]
            machine_id=f"{process_group}-1",
            status=MachineStartStatus.STARTED,
        )


def _install_cycle_fakes(
    monkeypatch: pytest.MonkeyPatch,
    demand: WorkerQueueDemand,
) -> tuple[FakeSession, list[str], list[datetime | None]]:
    session = FakeSession()
    applied: list[str] = []
    inspected_at: list[datetime | None] = []
    monkeypatch.setattr(worker_demand_monitor, "SessionLocal", lambda: session)
    monkeypatch.setattr(
        worker_demand_monitor,
        "set_website_worker_scope",
        lambda _db, enabled: applied.append(f"website:{enabled}"),
    )
    monkeypatch.setattr(
        worker_demand_monitor,
        "set_ingestion_worker_scope",
        lambda _db, enabled: applied.append(f"ingestion:{enabled}"),
    )

    def inspect(_db: FakeSession, *, now: datetime | None = None) -> WorkerQueueDemand:
        inspected_at.append(now)
        return demand

    monkeypatch.setattr(WorkerQueueDemandService, "inspect", staticmethod(inspect))
    return session, applied, inspected_at


def _stop_on_sleep(_seconds: float) -> NoReturn:
    raise StopLoop


def _install_cycle_clock(
    monkeypatch: pytest.MonkeyPatch,
    *,
    elapsed_seconds: float,
) -> list[float]:
    ticks = iter((100.0, 100.0 + elapsed_seconds))
    sleeps: list[float] = []
    monkeypatch.setattr(worker_demand_monitor, "monotonic", lambda: next(ticks))

    def stop_after_sleep(seconds: float) -> NoReturn:
        sleeps.append(seconds)
        raise StopLoop

    monkeypatch.setattr(worker_demand_monitor, "sleep", stop_after_sleep)
    return sleeps


def _install_active_loop_fakes(monkeypatch: pytest.MonkeyPatch) -> None:
    class LoopFlyService:
        def __init__(self, **_kwargs: object) -> None:
            pass

        def close(self) -> None:
            pass

    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        True,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_poll_seconds",
        2,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        SecretStr("opaque-test-token"),
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token_expires_at",
        None,
    )
    monkeypatch.setattr(worker_demand_monitor, "FlyMachineService", LoopFlyService)
    monkeypatch.setattr(
        worker_demand_monitor,
        "execute_once",
        lambda _service: worker_demand_monitor.DemandMonitorResult(
            demand=WorkerQueueDemand(website=False, ingestion=False),
            starts=(),
            failures=(),
        ),
    )


def test_execute_once_applies_both_scopes_and_starts_each_demanded_group(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Removing a scope or a demanded start must fail this cycle contract."""
    session, applied, inspected_at = _install_cycle_fakes(
        monkeypatch,
        WorkerQueueDemand(website=True, ingestion=True),
    )
    service = FakeFlyMachineService()
    now = datetime(2026, 8, 4, 12, 0, tzinfo=timezone.utc)

    result = worker_demand_monitor.execute_once(service, now=now)

    assert applied == ["website:True", "ingestion:True"]
    assert inspected_at == [now]
    assert service.started_groups == ["website", "ingestion"]
    assert result == worker_demand_monitor.DemandMonitorResult(
        demand=WorkerQueueDemand(website=True, ingestion=True),
        starts=(
            MachineStartResult(
                process_group="website",
                machine_id="website-1",
                status=MachineStartStatus.STARTED,
            ),
            MachineStartResult(
                process_group="ingestion",
                machine_id="ingestion-1",
                status=MachineStartStatus.STARTED,
            ),
        ),
        failures=(),
    )
    assert session.rolled_back is True
    assert session.closed is True


@pytest.mark.parametrize(
    ("demand", "expected_groups"),
    [
        (WorkerQueueDemand(website=False, ingestion=False), []),
        (WorkerQueueDemand(website=True, ingestion=False), ["website"]),
        (WorkerQueueDemand(website=False, ingestion=True), ["ingestion"]),
    ],
)
def test_execute_once_starts_only_groups_with_current_demand(
    monkeypatch: pytest.MonkeyPatch,
    demand: WorkerQueueDemand,
    expected_groups: list[str],
) -> None:
    """Starting an idle or opposite queue must fail this demand boundary."""
    _install_cycle_fakes(monkeypatch, demand)
    service = FakeFlyMachineService()

    result = worker_demand_monitor.execute_once(service)

    assert service.started_groups == expected_groups
    assert [start.process_group for start in result.starts] == expected_groups
    assert result.demand == demand
    assert result.failures == ()


def test_execute_once_isolates_group_failure_and_uses_secret_safe_diagnostics(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A website failure must not block ingestion or expose provider details."""
    _install_cycle_fakes(
        monkeypatch,
        WorkerQueueDemand(website=True, ingestion=True),
    )
    service = FakeFlyMachineService(failing_group="website")

    with caplog.at_level(logging.INFO, logger=worker_demand_monitor.logger.name):
        result = worker_demand_monitor.execute_once(service)

    assert service.started_groups == ["website", "ingestion"]
    assert [start.process_group for start in result.starts] == ["ingestion"]
    assert result.failures == ("website:FlyMachineTransientError",)
    assert "sensitive provider detail" not in caplog.text
    failure_record = next(
        record
        for record in caplog.records
        if record.getMessage() == "Worker start failed"
    )
    assert failure_record.process_group == "website"
    assert failure_record.machine_id is None
    assert failure_record.result == "failed"
    assert failure_record.failure_class == "FlyMachineTransientError"
    success_record = next(
        record
        for record in caplog.records
        if record.getMessage() == "Worker start completed"
    )
    assert success_record.process_group == "ingestion"
    assert success_record.machine_id == "ingestion-1"
    assert success_record.result == "started"
    assert success_record.failure_class is None


def test_execute_once_rolls_back_and_closes_when_inspection_raises(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A failed inspection must never leak its session or open transaction."""
    session, _, _ = _install_cycle_fakes(
        monkeypatch,
        WorkerQueueDemand(website=False, ingestion=False),
    )

    def fail_inspection(
        _db: FakeSession, *, now: datetime | None = None
    ) -> WorkerQueueDemand:
        raise RuntimeError("database unavailable")

    monkeypatch.setattr(
        WorkerQueueDemandService,
        "inspect",
        staticmethod(fail_inspection),
    )

    with pytest.raises(RuntimeError, match="database unavailable"):
        worker_demand_monitor.execute_once(FakeFlyMachineService())

    assert session.rolled_back is True
    assert session.closed is True


def test_demand_monitor_result_is_immutable() -> None:
    """Mutation of a completed cycle result must fail."""
    result = worker_demand_monitor.DemandMonitorResult(
        demand=WorkerQueueDemand(website=False, ingestion=False),
        starts=(),
        failures=(),
    )

    with pytest.raises(FrozenInstanceError):
        result.failures = ("changed",)  # type: ignore[misc]


def test_failure_tracker_reports_at_three_then_every_twelve_failed_cycles(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Changing the Sentry cadence from cycles 3, 15, 27 must fail."""
    captured: list[tuple[str, str | None]] = []
    monkeypatch.setattr(
        worker_demand_monitor.sentry_sdk,
        "capture_message",
        lambda message, level=None: captured.append((message, level)),
    )
    tracker = worker_demand_monitor._FailureTracker()

    for _ in range(27):
        tracker.record(("website:FlyMachineTransientError",))

    assert captured == [
        ("Worker demand monitor failures are continuing", "error"),
        ("Worker demand monitor failures are continuing", "error"),
        ("Worker demand monitor failures are continuing", "error"),
    ]


def test_failure_tracker_resets_after_a_successful_cycle(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A successful cycle must break the consecutive-failure threshold."""
    captures: list[str] = []
    monkeypatch.setattr(
        worker_demand_monitor.sentry_sdk,
        "capture_message",
        lambda message, level=None: captures.append(message),
    )
    tracker = worker_demand_monitor._FailureTracker()

    tracker.record(("website:FlyMachineTransientError",))
    tracker.record(("website:FlyMachineTransientError",))
    tracker.record(())
    tracker.record(("website:FlyMachineTransientError",))
    tracker.record(("website:FlyMachineTransientError",))
    assert captures == []

    tracker.record(("website:FlyMachineTransientError",))
    assert captures == ["Worker demand monitor failures are continuing"]


def test_transient_start_failure_is_logged_on_every_cycle(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Suppressing per-cycle logs while throttling Sentry must fail."""
    _install_cycle_fakes(
        monkeypatch,
        WorkerQueueDemand(website=True, ingestion=False),
    )
    service = FakeFlyMachineService(failing_group="website")

    with caplog.at_level(logging.ERROR, logger=worker_demand_monitor.logger.name):
        worker_demand_monitor.execute_once(service)
        worker_demand_monitor.execute_once(service)

    failure_logs = [
        record
        for record in caplog.records
        if record.getMessage() == "Worker start failed"
    ]
    assert len(failure_logs) == 2


def test_token_expiry_tracker_warns_at_thirty_days_and_sentry_at_seven(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Missing either expiry threshold or repeating either alert must fail."""
    captures: list[tuple[str, str | None]] = []
    monkeypatch.setattr(
        worker_demand_monitor.sentry_sdk,
        "capture_message",
        lambda message, level=None: captures.append((message, level)),
    )
    tracker = worker_demand_monitor._TokenExpiryTracker()

    with caplog.at_level(logging.WARNING, logger=worker_demand_monitor.logger.name):
        tracker.record(date(2026, 9, 3), today=date(2026, 8, 4))
        tracker.record(date(2026, 9, 3), today=date(2026, 8, 4))
        tracker.record(date(2026, 8, 11), today=date(2026, 8, 4))
        tracker.record(date(2026, 8, 11), today=date(2026, 8, 4))

    expiry_logs = [
        record
        for record in caplog.records
        if record.getMessage() == "Fly worker control token expiry is approaching"
    ]
    assert [(record.days_remaining, record.result) for record in expiry_logs] == [
        (30, "token_expiry_warning"),
        (7, "token_expiry_critical"),
    ]
    assert captures == [
        ("Fly worker control token expires within seven days", "warning")
    ]


def test_worker_loop_normal_cycle_sleeps_only_for_remaining_interval(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A 0.7-second inspection should leave 1.3 seconds in a two-second cycle."""
    _install_active_loop_fakes(monkeypatch)
    sleeps = _install_cycle_clock(monkeypatch, elapsed_seconds=0.7)

    with pytest.raises(StopLoop):
        worker_demand_monitor.worker_loop()

    assert sleeps == pytest.approx([1.3])


@pytest.mark.parametrize(
    ("monitor_enabled", "token"),
    [
        (False, SecretStr("unused-test-token")),
        (True, None),
    ],
    ids=("disabled", "missing-token"),
)
def test_worker_loop_branch_cycles_share_start_to_start_cadence(
    monkeypatch: pytest.MonkeyPatch,
    monitor_enabled: bool,
    token: SecretStr | None,
) -> None:
    """Disabled and missing-token cycles should subtract their branch work."""
    constructed: list[object] = []
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        monitor_enabled,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_poll_seconds",
        2,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        token,
    )
    monkeypatch.setattr(
        worker_demand_monitor,
        "FlyMachineService",
        lambda **kwargs: constructed.append(kwargs),
    )
    sleeps = _install_cycle_clock(monkeypatch, elapsed_seconds=0.7)

    with pytest.raises(StopLoop):
        worker_demand_monitor.worker_loop()

    assert constructed == []
    assert sleeps == pytest.approx([1.3])


def test_worker_loop_overrun_uses_bounded_minimum_sleep(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """An overlong cycle should yield briefly instead of entering a hot loop."""
    _install_active_loop_fakes(monkeypatch)
    sleeps = _install_cycle_clock(monkeypatch, elapsed_seconds=2.7)

    with pytest.raises(StopLoop):
        worker_demand_monitor.worker_loop()

    assert sleeps == pytest.approx([0.1])


def test_worker_loop_does_not_construct_fly_service_while_disabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Constructing a credentialed Fly client while disabled must fail."""
    constructed: list[object] = []
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        False,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        SecretStr("must-not-be-read"),
    )
    monkeypatch.setattr(
        worker_demand_monitor,
        "FlyMachineService",
        lambda **kwargs: constructed.append(kwargs),
    )
    monkeypatch.setattr(worker_demand_monitor, "sleep", _stop_on_sleep)

    with pytest.raises(StopLoop):
        worker_demand_monitor.worker_loop()

    assert constructed == []


def test_worker_loop_missing_token_fails_closed_without_constructing_client(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A missing token must never cause client construction or fallback auth."""
    constructed: list[object] = []
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        True,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        None,
    )
    monkeypatch.setattr(
        worker_demand_monitor,
        "FlyMachineService",
        lambda **kwargs: constructed.append(kwargs),
    )
    monkeypatch.setattr(worker_demand_monitor, "sleep", _stop_on_sleep)

    with (
        caplog.at_level(logging.ERROR, logger=worker_demand_monitor.logger.name),
        pytest.raises(StopLoop),
    ):
        worker_demand_monitor.worker_loop()

    assert constructed == []
    assert "Fly worker control token is missing" in caplog.text


def test_worker_loop_whitespace_token_is_normalized_before_missing_token_gate(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Whitespace configuration must reach the monitor as an absent token."""
    normalized_token = Settings(
        auth_dev_mode=False,
        fly_worker_control_token="  \t\n",
    ).fly_worker_control_token
    constructed: list[object] = []
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        True,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        normalized_token,
    )
    monkeypatch.setattr(
        worker_demand_monitor,
        "FlyMachineService",
        lambda **kwargs: constructed.append(kwargs),
    )
    monkeypatch.setattr(worker_demand_monitor, "sleep", _stop_on_sleep)

    with pytest.raises(StopLoop):
        worker_demand_monitor.worker_loop()

    assert normalized_token is None
    assert constructed == []


def test_worker_loop_passes_token_intact_and_closes_on_termination(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """The owned Fly client must close when the monitor loop terminates."""
    events: list[object] = []
    opaque_token = OpaqueSecretStr("monitor-must-not-materialize-this")

    class LoopFlyService:
        def __init__(self, **kwargs: object) -> None:
            events.append(("constructed", kwargs))

        def close(self) -> None:
            events.append("closed")

    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        True,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        opaque_token,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_app",
        "sidebar-test",
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_machines_api_base_url",
        "https://machines.invalid/v1",
    )
    monkeypatch.setattr(worker_demand_monitor, "FlyMachineService", LoopFlyService)
    monkeypatch.setattr(
        worker_demand_monitor,
        "execute_once",
        lambda _service: worker_demand_monitor.DemandMonitorResult(
            demand=WorkerQueueDemand(website=False, ingestion=False),
            starts=(),
            failures=(),
        ),
    )
    monkeypatch.setattr(worker_demand_monitor, "sleep", _stop_on_sleep)

    with pytest.raises(StopLoop):
        worker_demand_monitor.worker_loop()

    assert len(events) == 2
    constructed_event = events[0]
    assert isinstance(constructed_event, tuple)
    _, kwargs = constructed_event
    assert kwargs["app_name"] == "sidebar-test"
    assert kwargs["token"] is opaque_token
    assert kwargs["api_base_url"] == "https://machines.invalid/v1"
    assert events[1] == "closed"


def test_worker_loop_expiry_diagnostics_never_include_token(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """The control token must not appear in logs or Sentry expiry messages."""
    token = "fly-token-never-log-this"
    captures: list[str] = []

    class LoopFlyService:
        def __init__(self, **_kwargs: object) -> None:
            pass

        def close(self) -> None:
            return None

    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "worker_demand_monitor_enabled",
        True,
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token",
        SecretStr(token),
    )
    monkeypatch.setattr(
        worker_demand_monitor.settings,
        "fly_worker_control_token_expires_at",
        date(2026, 8, 11),
    )
    monkeypatch.setattr(worker_demand_monitor, "_today", lambda: date(2026, 8, 4))
    monkeypatch.setattr(worker_demand_monitor, "FlyMachineService", LoopFlyService)
    monkeypatch.setattr(
        worker_demand_monitor,
        "execute_once",
        lambda _service: worker_demand_monitor.DemandMonitorResult(
            demand=WorkerQueueDemand(website=False, ingestion=False),
            starts=(),
            failures=(),
        ),
    )
    monkeypatch.setattr(
        worker_demand_monitor.sentry_sdk,
        "capture_message",
        lambda message, level=None: captures.append(message),
    )
    monkeypatch.setattr(worker_demand_monitor, "sleep", _stop_on_sleep)

    with (
        caplog.at_level(logging.WARNING, logger=worker_demand_monitor.logger.name),
        pytest.raises(StopLoop),
    ):
        worker_demand_monitor.worker_loop()

    assert token not in caplog.text
    assert all(token not in message for message in captures)
