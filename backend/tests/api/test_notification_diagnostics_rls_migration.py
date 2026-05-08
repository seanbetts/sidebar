"""Tests for notification diagnostics RLS repair migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260506_0900-076_add_rls_to_notification_diagnostics_tables.py"
    )
    assert migration_path.exists()
    spec = importlib.util.spec_from_file_location(
        "migration_076_add_rls_to_notification_diagnostics_tables",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_enables_rls_for_notification_diagnostics_tables() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    protected_tables = {
        "notification_diagnostics_audit",
        "notification_scheduler_decisions",
        "notification_scheduler_heartbeat",
        "notification_scheduler_runs",
    }
    for table in protected_tables:
        assert f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY" in executed_sql
        assert any(
            f"DROP POLICY IF EXISTS {table}_notification_worker_operations" in s
            for s in executed_sql
        )
        policy = next(
            statement
            for statement in executed_sql
            if f"CREATE POLICY {table}_notification_worker_operations" in statement
        )
        assert "current_setting('app.notification_worker_scope', true)" in policy
        assert "= 'all'" in policy
        assert "WITH CHECK" in policy

    user_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY notification_diagnostics_audit_user_select" in statement
    )
    assert "FOR SELECT" in user_policy
    assert "user_id = (SELECT current_setting('app.user_id', true))" in user_policy

    user_insert_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY notification_diagnostics_audit_user_insert" in statement
    )
    assert "FOR INSERT" in user_insert_policy
    assert "WITH CHECK" in user_insert_policy
    assert "user_id = (SELECT current_setting('app.user_id', true))" in user_insert_policy

    decision_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY notification_scheduler_decisions_user_select" in statement
    )
    assert "FOR SELECT" in decision_policy
    assert "user_id = (SELECT current_setting('app.user_id', true))" in decision_policy

    decision_insert_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY notification_scheduler_decisions_user_insert" in statement
    )
    assert "FOR INSERT" in decision_insert_policy
    assert "WITH CHECK" in decision_insert_policy
    assert "user_id = (SELECT current_setting('app.user_id', true))" in decision_insert_policy

    for table in {"notification_scheduler_heartbeat", "notification_scheduler_runs"}:
        read_policy = next(
            statement
            for statement in executed_sql
            if f"CREATE POLICY {table}_backend_select" in statement
        )
        assert "FOR SELECT" in read_policy
        assert "current_setting('app.user_id', true)" in read_policy
        assert "IS NOT NULL" in read_policy


def test_downgrade_removes_notification_diagnostics_rls_policies() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.downgrade()

    protected_tables = {
        "notification_diagnostics_audit",
        "notification_scheduler_decisions",
        "notification_scheduler_heartbeat",
        "notification_scheduler_runs",
    }
    for table in protected_tables:
        assert any(
            f"DROP POLICY IF EXISTS {table}_notification_worker_operations" in s
            for s in executed_sql
        )
        assert f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY" in executed_sql

    assert any(
        "DROP POLICY IF EXISTS notification_diagnostics_audit_user_select" in s
        for s in executed_sql
    )
    assert any(
        "DROP POLICY IF EXISTS notification_scheduler_decisions_user_select" in s
        for s in executed_sql
    )
    assert any(
        "DROP POLICY IF EXISTS notification_scheduler_heartbeat_backend_select" in s
        for s in executed_sql
    )
    assert any(
        "DROP POLICY IF EXISTS notification_scheduler_runs_backend_select" in s
        for s in executed_sql
    )
