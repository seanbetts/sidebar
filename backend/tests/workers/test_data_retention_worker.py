"""Tests for the retention cleanup worker."""

from __future__ import annotations

from workers import data_retention_worker, worker_runner


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


def test_worker_runner_starts_data_retention_thread(monkeypatch):
    started: list[object] = []

    class FakeThread:
        def __init__(self, *, target, daemon):
            self._target = target
            self._daemon = daemon

        def start(self):
            started.append(self._target)

        def join(self):
            return None

    def retention_target() -> None:
        return None

    monkeypatch.setattr(worker_runner.threading, "Thread", FakeThread)
    monkeypatch.setattr(worker_runner, "_run_ingestion", lambda: None)
    monkeypatch.setattr(worker_runner, "_run_data_retention", retention_target)

    worker_runner.main()

    assert retention_target in started
