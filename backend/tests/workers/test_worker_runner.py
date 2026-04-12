"""Tests for the shared worker runner process composition."""

from workers import worker_runner


def test_worker_runner_starts_ingestion_and_notification_threads(monkeypatch):
    """Worker runner should start ingestion, notification, and retention threads."""
    started: list[tuple[str, bool]] = []

    class FakeThread:
        def __init__(self, *, target, daemon):
            started.append((target.__name__, daemon))

        def start(self):
            return None

        def join(self):
            return None

    monkeypatch.setattr(worker_runner.threading, "Thread", FakeThread)
    monkeypatch.setattr(worker_runner, "_run_ingestion", lambda: None)
    monkeypatch.setattr(worker_runner, "_run_notification_schedule", lambda: None)
    monkeypatch.setattr(worker_runner, "_run_data_retention", lambda: None)

    worker_runner.main()

    assert started == [
        ("<lambda>", True),
        ("<lambda>", True),
        ("<lambda>", True),
    ]


def test_worker_runner_does_not_start_website_worker(monkeypatch):
    """Worker runner should leave website processing to its dedicated process."""
    called: list[str] = []

    class FakeThread:
        def __init__(self, **_kwargs):
            pass

        def start(self):
            return None

        def join(self):
            return None

    monkeypatch.setattr(worker_runner.threading, "Thread", FakeThread)
    monkeypatch.setattr(worker_runner, "_run_ingestion", lambda: None)
    monkeypatch.setattr(worker_runner, "_run_notification_schedule", lambda: None)
    monkeypatch.setattr(
        worker_runner,
        "website_main",
        lambda: called.append("website"),
        raising=False,
    )

    worker_runner.main()

    assert called == []
