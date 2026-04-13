"""Tests for backend/scripts/fly_diagnostics.py."""

from __future__ import annotations

from scripts.fly_diagnostics import build_fly_summary


def test_summary_warns_when_machine_has_recent_restarts() -> None:
    """Machine restart signals should elevate the Fly summary."""
    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=[{"id": "machine-1", "state": "started", "restart_count": 3}],
        logs=[{"level": "error", "message": "boom"}],
    )

    assert result["status"] == "warn"
    assert result["data"]["machine_count"] == 1
    assert result["warnings"]


def test_summary_stays_ok_when_app_and_machines_are_healthy() -> None:
    """Healthy app and machine state should keep the Fly summary ok."""
    result = build_fly_summary(
        app={"name": "sidebar", "status": "deployed"},
        machines=[{"id": "machine-1", "state": "started", "restart_count": 0}],
        logs=[],
    )

    assert result["status"] == "ok"
    assert result["warnings"] == []
