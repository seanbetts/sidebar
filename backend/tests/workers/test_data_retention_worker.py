"""Tests for the retention cleanup worker."""

from __future__ import annotations

import logging

import pytest

from workers import data_retention_worker


class _FakeSession:
    """Minimal context-manager session for worker tests."""

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        return None


def test_run_once_calls_retention_service_with_configured_batch_size(monkeypatch):
    captured: dict[str, int] = {}

    def fake_run_cycle(_db, *, now=None, batch_size: int):
        captured["batch_size"] = batch_size
        return data_retention_worker.CleanupRunSummary(total_actions=2)

    monkeypatch.setattr(data_retention_worker, "run_retention_cycle", fake_run_cycle)
    monkeypatch.setattr(
        data_retention_worker,
        "set_retention_worker_scope",
        lambda *_args, **_kwargs: None,
    )
    monkeypatch.setattr(
        data_retention_worker,
        "_record_cleanup_metrics",
        lambda *_args, **_kwargs: None,
    )
    monkeypatch.setattr(
        data_retention_worker,
        "_session_factory",
        lambda: lambda: _FakeSession(),
    )
    monkeypatch.setattr(data_retention_worker.settings, "data_retention_batch_size", 25)

    summary = data_retention_worker.run_once()

    assert captured["batch_size"] == 25
    assert summary.total_actions == 2


def test_run_once_applies_retention_worker_scope_before_cleanup(monkeypatch):
    applied_scope: list[bool] = []

    class ScopeSession(_FakeSession):
        retention_scope_enabled = False

    def fake_set_retention_scope(db, *, enabled: bool) -> None:
        db.retention_scope_enabled = enabled
        applied_scope.append(enabled)

    def fake_run_cycle(db, *, now=None, batch_size: int):
        assert db.retention_scope_enabled is True
        return data_retention_worker.CleanupRunSummary(total_actions=1)

    monkeypatch.setattr(
        data_retention_worker,
        "set_retention_worker_scope",
        fake_set_retention_scope,
    )
    monkeypatch.setattr(data_retention_worker, "run_retention_cycle", fake_run_cycle)
    monkeypatch.setattr(
        data_retention_worker,
        "_record_cleanup_metrics",
        lambda *_args, **_kwargs: None,
    )
    monkeypatch.setattr(
        data_retention_worker,
        "_session_factory",
        lambda: lambda: ScopeSession(),
    )

    summary = data_retention_worker.run_once()

    assert applied_scope == [True]
    assert summary.total_actions == 1


def test_worker_loop_retries_failed_cycles_on_configured_cadence(
    monkeypatch,
    caplog,
) -> None:
    """The dedicated retention process should retain its existing retry behavior."""

    class StopLoop(BaseException):
        pass

    sleep_calls: list[int] = []

    monkeypatch.setattr(
        data_retention_worker,
        "run_once",
        lambda: (_ for _ in ()).throw(RuntimeError("retention failed")),
    )
    monkeypatch.setattr(
        data_retention_worker.settings,
        "data_retention_poll_seconds",
        123,
    )

    def stop_after_retry_sleep(seconds: int) -> None:
        sleep_calls.append(seconds)
        raise StopLoop

    monkeypatch.setattr(data_retention_worker.time, "sleep", stop_after_retry_sleep)

    with (
        caplog.at_level(logging.ERROR, logger=data_retention_worker.logger.name),
        pytest.raises(StopLoop),
    ):
        data_retention_worker.worker_loop()

    assert sleep_calls == [123]
    assert any(
        record.message == "Data retention worker crashed, retrying after delay"
        for record in caplog.records
    )


def test_worker_loop_propagates_failed_cycle_without_sleep_in_control_mode(
    monkeypatch,
    caplog,
) -> None:
    """The control runner must own logging and retry delay for retention failures."""

    class UnexpectedSleep(BaseException):
        pass

    sleep_calls: list[int] = []

    monkeypatch.setattr(
        data_retention_worker,
        "run_once",
        lambda: (_ for _ in ()).throw(RuntimeError("retention failed")),
    )

    def fail_on_inner_sleep(seconds: int) -> None:
        sleep_calls.append(seconds)
        raise UnexpectedSleep

    monkeypatch.setattr(data_retention_worker.time, "sleep", fail_on_inner_sleep)

    with (
        caplog.at_level(logging.ERROR, logger=data_retention_worker.logger.name),
        pytest.raises(RuntimeError, match="retention failed"),
    ):
        data_retention_worker.worker_loop(raise_on_error=True)

    assert sleep_calls == []
    assert not any(
        record.message == "Data retention worker crashed, retrying after delay"
        for record in caplog.records
    )
