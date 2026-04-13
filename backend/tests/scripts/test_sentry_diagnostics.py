"""Tests for backend/scripts/sentry_diagnostics.py."""

from __future__ import annotations

from scripts.sentry_diagnostics import build_sentry_summary


def test_summary_warns_when_unresolved_issues_exist() -> None:
    """Recent unresolved issues should elevate the Sentry summary."""
    result = build_sentry_summary(
        issues=[
            {
                "id": "1",
                "count": "12",
                "metadata": {"title": "ExampleError"},
            }
        ],
        events=[{"eventID": "abc123"}],
        releases=[{"version": "1.0.0"}],
    )

    assert result["status"] == "warn"
    assert result["data"]["unresolved_issue_count"] == 1
    assert result["warnings"]


def test_summary_stays_ok_when_issue_list_is_empty() -> None:
    """No unresolved issues should keep the Sentry summary healthy."""
    result = build_sentry_summary(
        issues=[],
        events=[{"eventID": "abc123"}],
        releases=[{"version": "1.0.0"}],
    )

    assert result["status"] == "ok"
    assert result["warnings"] == []
