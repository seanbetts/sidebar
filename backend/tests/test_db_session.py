"""Regression tests for database session module startup behavior."""

from __future__ import annotations

import uuid
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
from sqlalchemy import inspect
from sqlalchemy.exc import OperationalError, PendingRollbackError

from api.db import session as session_module
from api.models.website import Website


def test_session_import_succeeds_when_trace_website_content_lazy_load_is_enabled() -> None:
    """Enabling website content lazy-load tracing must not crash module import."""
    backend_dir = Path(__file__).resolve().parents[1]
    env = os.environ.copy()
    env["TESTING"] = "1"
    env["TEST_USER_ID"] = env.get("TEST_USER_ID", "test-user")
    env["TRACE_WEBSITE_CONTENT_LAZY_LOAD"] = "1"

    result = subprocess.run(
        [sys.executable, "-c", "import api.db.session"],
        cwd=backend_dir,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr


def test_record_website_column_lazy_load_stashes_sql_and_stack(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Column-load tracing should capture SQL and stack for the pending refresh."""
    website = Website(
        id=uuid.uuid4(),
        user_id="user-1",
        url="https://example.com",
        domain="example.com",
        title="Example",
        content="Body",
        metadata_={},
    )
    refresh_state = inspect(website)
    monkeypatch.setattr(
        session_module.traceback,
        "format_stack",
        lambda limit=12: ["frame-1\n", "frame-2\n", "frame-3\n"],
    )
    session_module._pending_website_column_lazy_loads.clear()

    session_module._record_website_column_lazy_load(
        SimpleNamespace(
            is_column_load=True,
            bind_arguments={"mapper": Website.__mapper__},
            load_options=SimpleNamespace(_refresh_state=refresh_state),
            statement="SELECT websites.source FROM websites WHERE websites.id = :pk_1",
        )
    )

    pending_trace = session_module._pending_website_column_lazy_loads[id(refresh_state)]
    assert pending_trace["sql"] == (
        "SELECT websites.source FROM websites WHERE websites.id = :pk_1"
    )
    assert pending_trace["stack"] == "frame-1\nframe-2\n"


def test_log_website_column_refresh_emits_structured_warning_and_clears_trace(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Refreshing any deferred Website column should log attrs, SQL, and stack."""
    website = Website(
        id=uuid.uuid4(),
        user_id="user-1",
        url="https://example.com",
        domain="example.com",
        title="Example",
        content="Body",
        metadata_={},
    )
    refresh_state = inspect(website)
    session_module._pending_website_column_lazy_loads.clear()
    session_module._pending_website_column_lazy_loads[id(refresh_state)] = {
        "sql": "SELECT websites.source FROM websites WHERE websites.id = :pk_1",
        "stack": "frame-1\nframe-2\n",
    }

    with caplog.at_level("WARNING"):
        session_module._log_website_column_refresh(
            website,
            context=None,
            attrs=frozenset({"source"}),
        )

    assert str(website.id) in caplog.text
    assert "attrs=source" in caplog.text
    assert "SELECT websites.source FROM websites WHERE websites.id = :pk_1" in caplog.text
    assert "frame-1" in caplog.text
    assert id(refresh_state) not in session_module._pending_website_column_lazy_loads


def test_after_begin_invalidates_and_reraises_disconnect(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Disconnects in after_begin must invalidate and bubble up for caller retry."""
    session = SimpleNamespace(info={})
    invalidated: list[BaseException] = []
    connection = SimpleNamespace(
        invalidate=lambda exc=None: invalidated.append(exc),
    )
    apply_calls = 0

    def fake_apply(
        _connection,
        _user_id,
        _force_public_search_path,
        _website_worker_scope=None,
    ) -> None:
        nonlocal apply_calls
        apply_calls += 1
        raise OperationalError(
            "SET LOCAL statement_timeout = :timeout_ms",
            {"timeout_ms": 8000},
            Exception("SSL connection has been closed unexpectedly"),
        )

    monkeypatch.setattr(session_module, "_apply_session_settings", fake_apply)

    with pytest.raises(OperationalError):
        session_module._set_app_user_id(
            session,
            transaction=object(),
            connection=connection,
        )

    assert apply_calls == 1
    assert len(invalidated) == 1


def test_after_begin_applies_worker_scope_from_session_info(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Worker-scope sessions should reapply website_worker_scope every transaction."""
    session = SimpleNamespace(info={"website_worker_scope": "all"})
    connection = SimpleNamespace()
    captured: dict[str, object] = {}

    def fake_apply(
        _connection,
        user_id,
        force_public_search_path,
        website_worker_scope,
    ) -> None:
        captured["user_id"] = user_id
        captured["force_public_search_path"] = force_public_search_path
        captured["website_worker_scope"] = website_worker_scope

    monkeypatch.setattr(session_module, "_apply_session_settings", fake_apply)

    session_module._set_app_user_id(
        session,
        transaction=object(),
        connection=connection,
    )

    assert captured == {
        "user_id": None,
        "force_public_search_path": False,
        "website_worker_scope": "all",
    }


class _DisconnectingSession:
    def __init__(self) -> None:
        self.info: dict[str, str] = {}
        self.execute_calls = 0
        self.rollback_calls = 0
        self.invalidate_calls = 0

    def execute(self, _statement, _params=None):
        self.execute_calls += 1
        if self.execute_calls == 1:
            raise OperationalError(
                "SET app.user_id = :user_id",
                {"user_id": "user-1"},
                Exception("SSL connection has been closed unexpectedly"),
            )
        if self.rollback_calls == 0:
            raise PendingRollbackError(
                "Can't reconnect until invalid transaction is rolled back."
            )
        return None

    def rollback(self) -> None:
        self.rollback_calls += 1

    def invalidate(self) -> None:
        self.invalidate_calls += 1


def test_set_session_user_id_rolls_back_before_retrying_disconnect() -> None:
    """Explicit session setup must rollback before reconnecting an invalid session."""
    db = _DisconnectingSession()

    session_module.set_session_user_id(db, "user-1")

    assert db.info["app_user_id"] == "user-1"
    assert db.execute_calls == 2
    assert db.rollback_calls == 1
    assert db.invalidate_calls == 1


def test_set_website_worker_scope_rolls_back_before_retrying_disconnect() -> None:
    """Worker scope setup must rollback before retrying a dropped connection."""
    db = _DisconnectingSession()

    session_module.set_website_worker_scope(db, enabled=True)

    assert db.info["website_worker_scope"] == "all"
    assert db.execute_calls == 2
    assert db.rollback_calls == 1
    assert db.invalidate_calls == 1
