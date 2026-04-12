"""Tests for backend/scripts/purge_user_data.py."""

from __future__ import annotations

from importlib import import_module
from types import SimpleNamespace


script_module = import_module("scripts.purge_user_data")


class _FakeSession:
    """Minimal context-manager session for CLI tests."""

    def __init__(self) -> None:
        self.info: dict[str, str] = {}

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        return None


def test_purge_user_data_cli_requires_confirmation(monkeypatch, capsys) -> None:
    called = False

    def fake_purge(_db, _user_id: str):
        nonlocal called
        called = True
        return None

    monkeypatch.setattr(script_module, "UserDataPurgeService", SimpleNamespace(purge_user_data=fake_purge))
    monkeypatch.setattr(script_module, "setup_environment", lambda **_kwargs: None)
    monkeypatch.setattr(script_module, "_session_factory", lambda: lambda: _FakeSession())
    monkeypatch.setattr(script_module, "_set_session_user_id", lambda _db, _user_id: None)

    exit_code = script_module.main(["--user-id", "user-1"])

    captured = capsys.readouterr()
    assert exit_code == 2
    assert "--yes" in captured.out
    assert called is False


def test_purge_user_data_cli_invokes_service(monkeypatch, capsys) -> None:
    called: dict[str, str] = {}

    def fake_purge(_db, user_id: str):
        called["user_id"] = user_id
        return SimpleNamespace(total_rows_deleted=3, storage_objects_deleted=1)

    monkeypatch.setattr(script_module, "UserDataPurgeService", SimpleNamespace(purge_user_data=fake_purge))
    monkeypatch.setattr(script_module, "setup_environment", lambda **_kwargs: None)
    monkeypatch.setattr(script_module, "_session_factory", lambda: lambda: _FakeSession())
    monkeypatch.setattr(script_module, "_set_session_user_id", lambda _db, _user_id: None)

    exit_code = script_module.main(["--user-id", "user-1", "--yes"])

    captured = capsys.readouterr()
    assert exit_code == 0
    assert called["user_id"] == "user-1"
    assert "total_rows_deleted=3" in captured.out
    assert "storage_objects_deleted=1" in captured.out
