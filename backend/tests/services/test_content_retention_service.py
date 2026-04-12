"""Tests for retention policy defaults and cleanup metrics."""

from __future__ import annotations

from api import metrics
from api.services.retention_policy import retention_policy_for


def test_retention_policy_defaults_match_design_doc() -> None:
    notes = retention_policy_for("notes")
    websites = retention_policy_for("websites")
    keys = retention_policy_for("user_ai_provider_keys")

    assert notes.full_retention_days == 7
    assert notes.total_retention_days == 90
    assert notes.degrade_payload is True
    assert websites.total_retention_days == 60
    assert keys.total_retention_days == 7
    assert keys.degrade_payload is False


def test_cleanup_metrics_exist() -> None:
    assert metrics.data_cleanup_actions_total is not None
    assert metrics.data_cleanup_duration_seconds is not None
    assert metrics.data_cleanup_backlog_age_seconds is not None
