"""Tests for backend/scripts/fly_diagnostics.py."""

from __future__ import annotations

from scripts.fly_diagnostics import build_fly_summary, _fetch_app, _fetch_logs


class _FakeResponse:
    def __init__(self, payload, *, text: str = "", status_code: int = 200) -> None:
        self._payload = payload
        self.text = text
        self.status_code = status_code

    def json(self):
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise RuntimeError(f"status={self.status_code}")


class _FakeSession:
    def __init__(self, response: _FakeResponse) -> None:
        self.response = response
        self.calls: list[dict[str, object]] = []

    def get(self, url: str, **kwargs):
        self.calls.append({"url": url, **kwargs})
        return self.response


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


def test_fetch_app_uses_bearer_authorization_header() -> None:
    """Machines API requests should keep using bearer auth."""
    session = _FakeSession(_FakeResponse({"status": "deployed"}))

    _fetch_app(session, "sidebar", token="fly-token")

    assert session.calls == [
        {
            "url": "https://api.machines.dev/v1/apps/sidebar",
            "headers": {"Authorization": "Bearer fly-token"},
            "timeout": 15,
        }
    ]


def test_fetch_logs_uses_raw_authorization_header() -> None:
    """Fly logs endpoint requires the raw FlyV1 token, not bearer auth."""
    session = _FakeSession(_FakeResponse({}, text='{"level":"info","message":"ok"}'))

    _fetch_logs(session, "sidebar", region="lhr", token="fly-token")

    assert session.calls == [
        {
            "url": "https://api.fly.io/api/v1/apps/sidebar/logs",
            "headers": {"Authorization": "fly-token"},
            "params": {"region": "lhr"},
            "timeout": 15,
        }
    ]
