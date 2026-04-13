"""Tests for retention-worker RLS scope migration behavior."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260413_2000-069_add_retention_worker_scope_to_cleanup_policies.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_069_add_retention_worker_scope_to_cleanup_policies",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_adds_retention_scope_to_cleanup_policies() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert any("DROP POLICY IF EXISTS notes_select_optimized ON notes" in s for s in executed_sql)
    assert any("DROP POLICY IF EXISTS websites_backend_update ON websites" in s for s in executed_sql)
    assert any("app.retention_worker_scope" in s for s in executed_sql)
    assert any(
        "CREATE POLICY website_processing_jobs_worker_scope" in s for s in executed_sql
    )
    assert any(
        "CREATE POLICY task_groups_user_isolation" in s for s in executed_sql
    )


def test_downgrade_removes_retention_scope_from_cleanup_policies() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.downgrade()

    assert any("DROP POLICY IF EXISTS notes_select_optimized ON notes" in s for s in executed_sql)
    assert not any(
        "current_setting('app.retention_worker_scope', true) = 'all'" in s
        for s in executed_sql
    )
    assert any(
        "CREATE POLICY notes_select_optimized" in s
        and "auth.uid()" in s
        for s in executed_sql
    )
