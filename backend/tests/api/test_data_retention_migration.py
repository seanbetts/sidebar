"""Tests for retention-tracking migration behavior."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260411_1800-068_add_retention_tracking_and_cleanup_indexes.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_068_add_retention_tracking_and_cleanup_indexes",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_adds_payload_purged_at_to_notes_and_websites() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []
    sleep_calls: list[float] = []

    class _AutocommitBlock:
        def __enter__(self):
            return None

        def __exit__(self, exc_type, exc, tb) -> None:
            return None

    class FakeBind:
        @staticmethod
        def execute(statement, *_args, **_kwargs) -> None:
            executed_sql.append(str(statement))

    class FakeOp:
        @staticmethod
        def get_bind():
            return FakeBind()

        @staticmethod
        def get_context():
            class _Context:
                @staticmethod
                def autocommit_block():
                    return _AutocommitBlock()

            return _Context()

    migration.op = FakeOp()
    migration.time.sleep = lambda seconds: sleep_calls.append(seconds)

    migration.upgrade()

    assert any(
        "ALTER TABLE notes ADD COLUMN IF NOT EXISTS payload_purged_at" in statement
        for statement in executed_sql
    )
    assert any(
        "ALTER TABLE websites ADD COLUMN IF NOT EXISTS payload_purged_at"
        in statement
        for statement in executed_sql
    )
    assert sleep_calls == []


def test_upgrade_creates_cleanup_indexes_for_operational_pruning() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class _AutocommitBlock:
        def __enter__(self):
            return None

        def __exit__(self, exc_type, exc, tb) -> None:
            return None

    class FakeBind:
        @staticmethod
        def execute(statement, *_args, **_kwargs) -> None:
            executed_sql.append(str(statement))

    class FakeOp:
        @staticmethod
        def get_bind():
            return FakeBind()

        @staticmethod
        def get_context():
            class _Context:
                @staticmethod
                def autocommit_block():
                    return _AutocommitBlock()

            return _Context()

    migration.op = FakeOp()

    migration.upgrade()

    assert any(
        "SET statement_timeout TO '20min'" in statement for statement in executed_sql
    )
    assert any(
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_website_jobs_updated_at "
        "ON website_processing_jobs (updated_at)" in statement
        for statement in executed_sql
    )
