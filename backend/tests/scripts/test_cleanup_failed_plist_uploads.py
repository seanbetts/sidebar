"""Tests for backend/scripts/cleanup_failed_plist_uploads.py."""

from __future__ import annotations

from importlib import import_module
from types import SimpleNamespace


script_module = import_module("scripts.cleanup_failed_plist_uploads")


class _FakeSession:
    """Minimal context-manager session for CLI tests."""

    def __init__(self) -> None:
        self.info: dict[str, str] = {}

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        return None


def test_cleanup_failed_plist_uploads_cli_previews_all_users_by_default(
    monkeypatch,
    capsys,
) -> None:
    called: dict[str, object] = {}
    retention_scope: list[bool] = []

    def fake_cleanup(_db, **kwargs):
        called.update(kwargs)
        return SimpleNamespace(
            dry_run=True,
            matched_files=6,
            deleted_files=0,
            matched_users=1,
        )

    monkeypatch.setattr(
        script_module,
        "PlistUploadCleanupService",
        SimpleNamespace(cleanup_candidates=fake_cleanup),
    )
    monkeypatch.setattr(script_module, "setup_environment", lambda **_kwargs: None)
    monkeypatch.setattr(script_module, "_session_factory", lambda: lambda: _FakeSession())
    monkeypatch.setattr(
        script_module,
        "_set_retention_worker_scope",
        lambda _db, enabled: retention_scope.append(enabled),
    )
    monkeypatch.setattr(script_module, "_set_session_user_id", lambda _db, _user_id: None)

    exit_code = script_module.main([])

    captured = capsys.readouterr()
    assert exit_code == 0
    assert called["user_id"] is None
    assert called["dry_run"] is True
    assert retention_scope == [True]
    assert "dry_run=True" in captured.out
    assert "matched_files=6" in captured.out


def test_cleanup_failed_plist_uploads_cli_executes_for_specific_user(
    monkeypatch,
    capsys,
) -> None:
    called: dict[str, object] = {}
    scoped_users: list[str] = []

    def fake_cleanup(_db, **kwargs):
        called.update(kwargs)
        return SimpleNamespace(
            dry_run=False,
            matched_files=6,
            deleted_files=6,
            matched_users=1,
        )

    monkeypatch.setattr(
        script_module,
        "PlistUploadCleanupService",
        SimpleNamespace(cleanup_candidates=fake_cleanup),
    )
    monkeypatch.setattr(script_module, "setup_environment", lambda **_kwargs: None)
    monkeypatch.setattr(script_module, "_session_factory", lambda: lambda: _FakeSession())
    monkeypatch.setattr(script_module, "_set_retention_worker_scope", lambda _db, enabled: None)
    monkeypatch.setattr(
        script_module,
        "_set_session_user_id",
        lambda _db, user_id: scoped_users.append(user_id),
    )

    exit_code = script_module.main(["--user-id", "user-1", "--yes"])

    captured = capsys.readouterr()
    assert exit_code == 0
    assert scoped_users == ["user-1"]
    assert called["user_id"] == "user-1"
    assert called["dry_run"] is False
    assert "deleted_files=6" in captured.out
