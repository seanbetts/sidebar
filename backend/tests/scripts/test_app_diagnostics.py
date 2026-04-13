"""Tests for backend/scripts/app_diagnostics.py."""

from __future__ import annotations

from scripts.app_diagnostics import build_app_summary


def test_summary_warns_when_stalled_jobs_exist() -> None:
    """Stale queue entries should elevate the app diagnostics summary."""
    result = build_app_summary(
        queue_counts={
            "website_processing_jobs": {"queued": 1, "processing": 2},
            "file_processing_jobs": {"queued": 0, "processing": 1},
        },
        stale_jobs=[
            {
                "queue": "website_processing_jobs",
                "status": "processing",
                "stale_count": 2,
            }
        ],
    )

    assert result["status"] == "warn"
    assert result["data"]["stale_job_count"] == 2
    assert result["warnings"]


def test_summary_keeps_ok_status_when_queues_are_healthy() -> None:
    """Healthy queues should remain ok even when jobs exist."""
    result = build_app_summary(
        queue_counts={
            "website_processing_jobs": {"queued": 2, "processing": 1},
            "file_processing_jobs": {"queued": 1, "processing": 0},
        },
        stale_jobs=[],
    )

    assert result["status"] == "ok"
    assert result["data"]["stale_job_count"] == 0
    assert result["warnings"] == []


def test_summary_ignores_terminal_job_statuses_in_stale_results() -> None:
    """Terminal statuses should not be counted as stalled work."""
    result = build_app_summary(
        queue_counts={
            "website_processing_jobs": {"completed": 10, "failed": 3},
            "file_processing_jobs": {"ready": 7},
        },
        stale_jobs=[
            {
                "queue": "website_processing_jobs",
                "status": "failed",
                "stale_count": 4,
            }
        ],
    )

    assert result["status"] == "ok"
    assert result["data"]["stale_job_count"] == 0
    assert result["data"]["stale_jobs"] == []
    assert result["warnings"] == []
