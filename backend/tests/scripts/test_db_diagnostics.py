"""Tests for backend/scripts/db_diagnostics.py."""

from __future__ import annotations

from scripts.db_diagnostics import build_db_summary


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
