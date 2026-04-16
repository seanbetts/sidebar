"""Tests for device installation RLS migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260416_1900-070_add_rls_to_device_installations.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_070_add_rls_to_device_installations",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_enables_device_installation_rls_and_policies() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert "ALTER TABLE device_installations ENABLE ROW LEVEL SECURITY" in executed_sql
    assert (
        "ALTER TABLE device_installation_users ENABLE ROW LEVEL SECURITY" in executed_sql
    )
    assert (
        "DROP POLICY IF EXISTS device_installations_backend_operations "
        "ON device_installations"
    ) in executed_sql
    assert (
        "DROP POLICY IF EXISTS device_installation_users_backend_operations "
        "ON device_installation_users"
    ) in executed_sql
    assert (
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    ) in executed_sql
    assert (
        "DROP POLICY IF EXISTS device_installation_users_user_isolation "
        "ON device_installation_users"
    ) in executed_sql

    installation_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY device_installations_user_isolation" in statement
    )
    assert "device_installation_users" in installation_policy
    assert "installation_pk" in installation_policy
    assert "unbound_at IS NULL" in installation_policy
    assert "user_id =" in installation_policy
    assert "current_setting('app.user_id', true)" in installation_policy
    assert "auth.uid()" in installation_policy

    user_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY device_installation_users_user_isolation" in statement
    )
    assert "user_id = (SELECT current_setting('app.user_id', true))" in user_policy
    assert "user_id = (SELECT auth.uid()::text)" in user_policy

    backend_policies = [
        statement
        for statement in executed_sql
        if "CREATE POLICY" in statement and "backend_operations" in statement
    ]
    assert len(backend_policies) == 2
    assert all("current_setting('app.user_id', true) IS NOT NULL" in s for s in backend_policies)


def test_downgrade_removes_device_installation_policies() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.downgrade()

    assert (
        "DROP POLICY IF EXISTS device_installations_backend_operations "
        "ON device_installations"
    ) in executed_sql
    assert (
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    ) in executed_sql
    assert (
        "DROP POLICY IF EXISTS device_installation_users_backend_operations "
        "ON device_installation_users"
    ) in executed_sql
    assert (
        "DROP POLICY IF EXISTS device_installation_users_user_isolation "
        "ON device_installation_users"
    ) in executed_sql
    assert "ALTER TABLE device_installations DISABLE ROW LEVEL SECURITY" in executed_sql
    assert (
        "ALTER TABLE device_installation_users DISABLE ROW LEVEL SECURITY" in executed_sql
    )
