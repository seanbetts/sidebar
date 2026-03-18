"""Tests for user_skill_states RLS migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260318_1200-063_add_rls_to_user_skill_states.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_063_add_rls_to_user_skill_states",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_user_skill_states_rls_migration_enables_backend_user_isolation() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert "ALTER TABLE user_skill_states ENABLE ROW LEVEL SECURITY" in executed_sql
    assert (
        "DROP POLICY IF EXISTS user_skill_states_user_isolation "
        "ON user_skill_states"
    ) in executed_sql
    create_policy = next(
        statement
        for statement in executed_sql
        if "CREATE POLICY user_skill_states_user_isolation" in statement
    )
    assert "current_setting('app.user_id', true)" in create_policy
    assert "auth.uid()" not in create_policy


def test_user_skill_states_rls_migration_downgrade_removes_policy() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.downgrade()

    assert (
        "DROP POLICY IF EXISTS user_skill_states_user_isolation "
        "ON user_skill_states"
    ) in executed_sql
    assert "ALTER TABLE user_skill_states DISABLE ROW LEVEL SECURITY" in executed_sql
