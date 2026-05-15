"""Tests for Realtime Data API grant migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path


EXPECTED_REALTIME_TABLES = {
    "notes",
    "websites",
    "ingested_files",
    "file_processing_jobs",
    "tasks",
    "task_projects",
    "task_groups",
}


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260515_1200-077_grant_realtime_table_select.py"
    )
    assert migration_path.exists()
    spec = importlib.util.spec_from_file_location(
        "migration_077_grant_realtime_table_select",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_grants_authenticated_select_only_for_realtime_tables() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    grant = _only_statement_containing(executed_sql, "GRANT SELECT ON TABLE")
    normalized_grant = _normalize_sql(grant)
    assert "TO authenticated" in normalized_grant
    assert "anon" not in normalized_grant
    assert "INSERT" not in normalized_grant
    assert "UPDATE" not in normalized_grant
    assert "DELETE" not in normalized_grant
    for table in EXPECTED_REALTIME_TABLES:
        assert f"public.{table}" in normalized_grant


def test_downgrade_revokes_authenticated_select_for_realtime_tables() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.downgrade()

    revoke = _only_statement_containing(executed_sql, "REVOKE SELECT ON TABLE")
    normalized_revoke = _normalize_sql(revoke)
    assert "FROM authenticated" in normalized_revoke
    assert "anon" not in normalized_revoke
    for table in EXPECTED_REALTIME_TABLES:
        assert f"public.{table}" in normalized_revoke


def _only_statement_containing(statements: list[str], needle: str) -> str:
    matches = [statement for statement in statements if needle in _normalize_sql(statement)]
    assert len(matches) == 1
    return matches[0]


def _normalize_sql(statement: str) -> str:
    return " ".join(statement.split())
