"""Retention policy definitions for cleanup infrastructure."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta


@dataclass(frozen=True)
class RetentionPolicy:
    """Retention windows for a cleanup-managed table."""

    table_name: str
    full_retention_days: int
    total_retention_days: int
    degrade_payload: bool = False


_POLICIES: dict[str, RetentionPolicy] = {
    "notes": RetentionPolicy(
        table_name="notes",
        full_retention_days=7,
        total_retention_days=90,
        degrade_payload=True,
    ),
    "websites": RetentionPolicy(
        table_name="websites",
        full_retention_days=7,
        total_retention_days=60,
        degrade_payload=True,
    ),
    "ingested_files": RetentionPolicy(
        table_name="ingested_files",
        full_retention_days=30,
        total_retention_days=30,
    ),
    "tasks": RetentionPolicy(
        table_name="tasks",
        full_retention_days=60,
        total_retention_days=60,
    ),
    "task_projects": RetentionPolicy(
        table_name="task_projects",
        full_retention_days=60,
        total_retention_days=60,
    ),
    "task_groups": RetentionPolicy(
        table_name="task_groups",
        full_retention_days=60,
        total_retention_days=60,
    ),
    "user_ai_provider_keys": RetentionPolicy(
        table_name="user_ai_provider_keys",
        full_retention_days=7,
        total_retention_days=7,
    ),
    "website_processing_jobs": RetentionPolicy(
        table_name="website_processing_jobs",
        full_retention_days=0,
        total_retention_days=7,
    ),
    "file_processing_jobs": RetentionPolicy(
        table_name="file_processing_jobs",
        full_retention_days=0,
        total_retention_days=7,
    ),
    "task_operation_log": RetentionPolicy(
        table_name="task_operation_log",
        full_retention_days=0,
        total_retention_days=14,
    ),
}


def retention_policy_for(table_name: str) -> RetentionPolicy:
    """Return the configured retention policy for a table name."""
    return _POLICIES[table_name]


def full_retention_cutoff(policy: RetentionPolicy, *, now: datetime) -> datetime:
    """Return the timestamp after which full payload retention expires."""
    return now - timedelta(days=policy.full_retention_days)


def total_retention_cutoff(policy: RetentionPolicy, *, now: datetime) -> datetime:
    """Return the timestamp after which rows are eligible for final deletion."""
    return now - timedelta(days=policy.total_retention_days)
