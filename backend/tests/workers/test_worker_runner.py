"""Tests for the shared control-worker runner process."""

from __future__ import annotations

import logging
from collections.abc import Callable
from functools import partial

import pytest

from workers import worker_runner


class _RecordingThread:
    """Record thread configuration without starting infinite supervisors."""

    instances: list[_RecordingThread] = []
    events: list[str] = []

    def __init__(
        self,
        *,
        name: str = "<unnamed>",
        target: Callable[[], None],
        daemon: bool,
    ) -> None:
        self.name = name
        self.target = target
        self.daemon = daemon
        self.instances.append(self)

    def start(self) -> None:
        """Record that the supervisor was started."""
        self.events.append(f"start:{self.name}")

    def join(self) -> None:
        """Record which supervisor keeps the process alive."""
        self.events.append(f"join:{self.name}")


@pytest.fixture(autouse=True)
def _reset_recording_threads() -> None:
    """Keep thread recordings isolated between tests."""
    _RecordingThread.instances = []
    _RecordingThread.events = []


def test_worker_runner_starts_all_control_threads_before_joining_notification(
    monkeypatch,
) -> None:
    """The process should start three named daemon supervisors in order."""
    initialized: list[tuple[str, str]] = []

    monkeypatch.setattr(worker_runner.threading, "Thread", _RecordingThread)
    monkeypatch.setattr(
        worker_runner,
        "initialize_script_sentry",
        lambda script_name, *, process_type: initialized.append(
            (script_name, process_type)
        ),
    )

    worker_runner.main()

    assert [thread.name for thread in _RecordingThread.instances] == [
        "notification",
        "retention",
        "worker-demand",
    ]
    assert [thread.daemon for thread in _RecordingThread.instances] == [
        True,
        True,
        True,
    ]
    assert _RecordingThread.events == [
        "start:notification",
        "start:retention",
        "start:worker-demand",
        "join:notification",
    ]
    assert initialized == [("workers.worker_runner", "worker")]

    supervisor_targets = {
        thread.name: thread.target for thread in _RecordingThread.instances
    }
    for name, target in supervisor_targets.items():
        assert isinstance(target, partial)
        assert target.func is worker_runner._supervise
        assert target.args[0] == name

    notification_target = supervisor_targets["notification"].args[1]
    retention_target = supervisor_targets["retention"].args[1]
    demand_target = supervisor_targets["worker-demand"].args[1]

    assert isinstance(notification_target, partial)
    assert notification_target.func is worker_runner.notification_loop
    assert notification_target.keywords == {"raise_on_error": True}
    assert isinstance(retention_target, partial)
    assert retention_target.func is worker_runner.data_retention_loop
    assert retention_target.keywords == {"raise_on_error": True}
    assert demand_target is worker_runner.worker_demand_loop


def test_worker_runner_does_not_invoke_ingestion(monkeypatch) -> None:
    """The control process should leave ingestion to its dedicated process."""
    ingestion_calls: list[str] = []

    monkeypatch.setattr(worker_runner.threading, "Thread", _RecordingThread)
    monkeypatch.setattr(
        worker_runner,
        "ingestion_loop",
        lambda: ingestion_calls.append("ingestion"),
        raising=False,
    )
    monkeypatch.setattr(
        worker_runner,
        "initialize_script_sentry",
        lambda *_args, **_kwargs: None,
    )

    worker_runner.main()

    assert ingestion_calls == []
    assert [thread.name for thread in _RecordingThread.instances] == [
        "notification",
        "retention",
        "worker-demand",
    ]


def test_crashed_control_loop_retries_without_invoking_siblings(
    monkeypatch,
    caplog,
) -> None:
    """A crashed loop should retry in only its own supervisor after two seconds."""
    calls = {"notification": 0, "retention": 0, "worker-demand": 0}
    sleeps: list[int] = []

    def notification_target(*, raise_on_error: bool = False) -> None:
        calls["notification"] += 1
        if not raise_on_error:
            raise KeyboardInterrupt

    def retention_target(*, raise_on_error: bool = False) -> None:
        calls["retention"] += 1
        if not raise_on_error:
            raise KeyboardInterrupt
        if calls["retention"] == 1:
            raise RuntimeError("retention failed")
        raise KeyboardInterrupt

    def demand_target() -> None:
        calls["worker-demand"] += 1

    monkeypatch.setattr(worker_runner.threading, "Thread", _RecordingThread)
    monkeypatch.setattr(worker_runner, "notification_loop", notification_target)
    monkeypatch.setattr(worker_runner, "data_retention_loop", retention_target)
    monkeypatch.setattr(worker_runner, "worker_demand_loop", demand_target)
    monkeypatch.setattr(worker_runner, "sleep", sleeps.append)
    monkeypatch.setattr(
        worker_runner,
        "initialize_script_sentry",
        lambda *_args, **_kwargs: None,
    )
    worker_runner.main()
    retention_supervisors = [
        thread.target
        for thread in _RecordingThread.instances
        if thread.name == "retention"
    ]
    assert len(retention_supervisors) == 1
    retention_supervisor = retention_supervisors[0]

    with (
        caplog.at_level(logging.ERROR, logger=worker_runner.logger.name),
        pytest.raises(KeyboardInterrupt),
    ):
        retention_supervisor()

    assert calls == {"notification": 0, "retention": 2, "worker-demand": 0}
    assert sleeps == [2]
    crash_record = next(
        record for record in caplog.records if record.message == "Control loop crashed"
    )
    assert crash_record.control_loop == "retention"


def test_returned_control_loop_is_logged_and_retried(monkeypatch, caplog) -> None:
    """An unexpected normal return should be logged before a two-second retry."""
    calls = 0
    sleeps: list[int] = []

    def returning_target() -> None:
        nonlocal calls
        calls += 1
        if calls == 2:
            raise KeyboardInterrupt

    monkeypatch.setattr(worker_runner, "sleep", sleeps.append)
    supervisor = getattr(worker_runner, "_supervise", None)
    assert supervisor is not None

    with (
        caplog.at_level(logging.ERROR, logger=worker_runner.logger.name),
        pytest.raises(KeyboardInterrupt),
    ):
        supervisor("notification", returning_target)

    assert calls == 2
    assert sleeps == [2]
    exit_record = next(
        record
        for record in caplog.records
        if record.message == "Control loop exited unexpectedly"
    )
    assert exit_record.control_loop == "notification"
