"""Tests for backend/scripts/db_diagnostics.py."""

from __future__ import annotations

import pytest

from scripts.db_diagnostics import (
    _execute_read_only_sql,
    _validate_read_only_sql,
    build_db_summary,
)


def test_summary_warns_on_idle_transactions() -> None:
    """Idle-in-transaction sessions should raise the summary severity."""
    result = build_db_summary(
        sessions_by_state=[
            {
                "application_name": "Supavisor",
                "state": "idle in transaction",
                "session_count": 2,
            }
        ],
        idle_transactions=[{"pid": 123, "xact_age_seconds": 600}],
        blockers=[],
        top_queries=[
            {"query": "select 1", "calls": 10, "total_exec_time": 5.0},
        ],
    )

    assert result["status"] == "warn"
    assert result["data"]["idle_in_transaction_count"] == 1
    assert result["warnings"]


def test_summary_includes_blocker_count() -> None:
    """Active blockers should be surfaced in the summary payload."""
    result = build_db_summary(
        sessions_by_state=[],
        idle_transactions=[],
        blockers=[{"blocked_pid": 1, "blocker_pid": 2}],
        top_queries=[],
    )

    assert result["status"] == "warn"
    assert result["data"]["blocker_count"] == 1


def test_summary_marks_top_queries_unavailable_without_failing_whole_command() -> None:
    """Missing pg_stat_statements should degrade one section, not the command."""
    result = build_db_summary(
        sessions_by_state=[],
        idle_transactions=[],
        blockers=[],
        top_queries=None,
    )

    assert result["status"] == "ok"
    assert result["data"]["top_queries_available"] is False
    assert result["warnings"] == ["pg_stat_statements unavailable"]


def test_validate_read_only_sql_accepts_single_select_statement() -> None:
    """A single SELECT statement should be accepted."""
    sql = _validate_read_only_sql("select id, url from websites limit 5")

    assert sql == "select id, url from websites limit 5"


def test_validate_read_only_sql_rejects_mutating_statement() -> None:
    """Mutating SQL should be rejected before execution."""
    with pytest.raises(ValueError, match="read-only"):
        _validate_read_only_sql("delete from websites where id = '123'")


def test_validate_read_only_sql_rejects_multiple_statements() -> None:
    """Only one statement should be allowed."""
    with pytest.raises(ValueError, match="single statement"):
        _validate_read_only_sql("select 1; select 2")


def test_execute_read_only_sql_sets_transaction_read_only() -> None:
    """Execution should switch the transaction to read-only before the query."""

    class FakeResult:
        def mappings(self) -> "FakeResult":
            return self

        def __iter__(self):
            yield {"database_name": "postgres", "database_user": "sidebar_app"}

    class FakeTransaction:
        def __init__(self, events: list[tuple[str, str]]) -> None:
            self.events = events

        def __enter__(self) -> "FakeTransaction":
            self.events.append(("transaction", "begin"))
            return self

        def __exit__(self, exc_type, exc, tb) -> None:
            self.events.append(("transaction", "end"))
            return None

    class FakeConnection:
        def __init__(self) -> None:
            self.events: list[tuple[str, str]] = []

        def begin(self) -> FakeTransaction:
            return FakeTransaction(self.events)

        def exec_driver_sql(self, statement: str) -> None:
            self.events.append(("driver_sql", statement))

        def execute(self, statement):  # noqa: ANN001
            self.events.append(("execute", str(statement)))
            return FakeResult()

    connection = FakeConnection()

    rows = _execute_read_only_sql(
        connection,
        "select current_database() as database_name, current_user as database_user",
    )

    assert rows == [{"database_name": "postgres", "database_user": "sidebar_app"}]
    assert connection.events == [
        ("transaction", "begin"),
        ("driver_sql", "SET TRANSACTION READ ONLY"),
        (
            "execute",
            "select current_database() as database_name, current_user as database_user",
        ),
        ("transaction", "end"),
    ]
