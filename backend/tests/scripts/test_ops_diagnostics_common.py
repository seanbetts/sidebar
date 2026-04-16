"""Tests for backend/scripts/ops_diagnostics_common.py."""

from __future__ import annotations

import io
import json
import uuid
from decimal import Decimal
from datetime import UTC, datetime
from pathlib import Path

from scripts.ops_diagnostics_common import (
    EXIT_CONFIG,
    EXIT_FAILURE,
    EXIT_OK,
    build_result,
    masked_url_summary,
    print_json_result,
)


def test_masked_url_summary_hides_password() -> None:
    """URL summaries should not include credentials."""
    summary = masked_url_summary(
        "postgresql://user:secret@example.com:6543/postgres?sslmode=require"
    )

    assert "secret" not in summary
    assert "user=user" in summary
    assert "host=example.com" in summary
    assert "port=6543" in summary
    assert "db=postgres" in summary


def test_build_result_uses_expected_envelope() -> None:
    """Result envelopes should match the shared JSON contract."""
    result = build_result(
        target="db",
        command="summary",
        status="warn",
        data={"idle_in_transaction": 2},
        warnings=["found idle transactions"],
        errors=[],
        generated_at="2026-04-13T12:00:00Z",
    )

    assert result == {
        "target": "db",
        "command": "summary",
        "status": "warn",
        "generated_at": "2026-04-13T12:00:00Z",
        "data": {"idle_in_transaction": 2},
        "warnings": ["found idle transactions"],
        "errors": [],
    }


def test_print_json_result_serializes_envelope() -> None:
    """JSON printer should emit valid JSON to the provided stream."""
    result = build_result(
        target="fly",
        command="status",
        status="ok",
        data={"machines": 2},
        generated_at="2026-04-13T12:00:00Z",
    )

    stream = io.StringIO()
    print_json_result(result, stream=stream)

    parsed = json.loads(stream.getvalue())
    assert parsed["target"] == "fly"
    assert parsed["data"]["machines"] == 2


def test_print_json_result_serializes_datetime_and_uuid_values() -> None:
    """JSON printer should stringify common DB result scalar types."""
    result = build_result(
        target="db",
        command="sql",
        status="ok",
        data={
            "rows": [
                {
                    "id": uuid.UUID("12345678-1234-5678-1234-567812345678"),
                    "created_at": datetime(2026, 4, 13, 18, 0, tzinfo=UTC),
                }
            ]
        },
        generated_at="2026-04-13T12:00:00Z",
    )

    stream = io.StringIO()
    print_json_result(result, stream=stream)

    parsed = json.loads(stream.getvalue())
    assert parsed["data"]["rows"][0]["id"] == "12345678-1234-5678-1234-567812345678"
    assert parsed["data"]["rows"][0]["created_at"] == "2026-04-13T18:00:00+00:00"


def test_print_json_result_serializes_decimal_values() -> None:
    """JSON printer should convert Decimal values returned by DB stats queries."""
    result = build_result(
        target="db",
        command="top-queries",
        status="ok",
        data={
            "rows": [
                {
                    "calls": 7,
                    "mean_exec_time": Decimal("5.41"),
                    "total_exec_time": Decimal("16144589.12"),
                }
            ]
        },
        generated_at="2026-04-13T12:00:00Z",
    )

    stream = io.StringIO()
    print_json_result(result, stream=stream)

    parsed = json.loads(stream.getvalue())
    assert parsed["data"]["rows"][0]["calls"] == 7
    assert parsed["data"]["rows"][0]["mean_exec_time"] == 5.41
    assert parsed["data"]["rows"][0]["total_exec_time"] == 16144589.12


def test_exit_codes_are_stable() -> None:
    """Shared exit-code constants should stay aligned with the wrapper contract."""
    assert EXIT_OK == 0
    assert EXIT_FAILURE == 1
    assert EXIT_CONFIG == 2


def test_load_local_env_reads_repo_root_env_file(tmp_path: Path, monkeypatch) -> None:
    """Repo-root .env.local values should be loaded when not already set."""
    from scripts.ops_diagnostics_common import load_local_env

    (tmp_path / ".env.local").write_text(
        "OPS_DB_URL=postgresql://example\n",
        encoding="utf-8",
    )
    backend_dir = tmp_path / "backend"
    backend_dir.mkdir()
    monkeypatch.delenv("OPS_DB_URL", raising=False)

    load_local_env(repo_root=tmp_path)

    assert backend_dir.exists()
    assert Path(tmp_path / ".env.local").exists()
    assert __import__("os").environ["OPS_DB_URL"] == "postgresql://example"
