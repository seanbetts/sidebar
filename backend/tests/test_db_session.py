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
