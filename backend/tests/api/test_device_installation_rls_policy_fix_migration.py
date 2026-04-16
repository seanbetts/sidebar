"""Tests for the device installation RLS policy fix migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260416_1930-071_fix_device_installation_rls_outer_reference.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_071_fix_device_installation_rls_outer_reference",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_recreates_installation_user_isolation_with_outer_reference() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert (
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    ) in executed_sql

    installation_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY device_installations_user_isolation" in statement
    )
    assert "device_installation_users.installation_pk = device_installations.id" in (
        installation_policy
    )
    assert "device_installation_users.unbound_at IS NULL" in installation_policy
    assert "device_installation_users.user_id" in installation_policy
    assert "current_setting('app.user_id', true)" in installation_policy
    assert "auth.uid()" in installation_policy


def test_downgrade_restores_original_installation_user_isolation_policy() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.downgrade()

    assert (
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    ) in executed_sql

    installation_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY device_installations_user_isolation" in statement
    )
    assert "installation_pk = id" in installation_policy
