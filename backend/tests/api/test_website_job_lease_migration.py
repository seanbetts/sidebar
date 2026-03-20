"""Tests for website job lease migration publication handling."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest.mock import MagicMock


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260320_1200-064_add_website_job_lease_columns.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_064_add_website_job_lease_columns",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_skips_realtime_publication_when_missing() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []
    scalar_results = [False]

    fake_bind = MagicMock()
    fake_bind.scalar.side_effect = scalar_results

    class FakeOp:
        @staticmethod
        def add_column(*args, **kwargs) -> None:
            return None

        @staticmethod
        def create_index(*args, **kwargs) -> None:
            return None

        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

        @staticmethod
        def get_bind():
            return fake_bind

    migration.op = FakeOp()

    migration.upgrade()

    assert not any(
        "ALTER PUBLICATION supabase_realtime ADD TABLE website_processing_jobs"
        in statement
        for statement in executed_sql
    )


def test_downgrade_skips_realtime_publication_when_missing() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []
    scalar_results = [False]

    fake_bind = MagicMock()
    fake_bind.scalar.side_effect = scalar_results

    class FakeOp:
        @staticmethod
        def drop_index(*args, **kwargs) -> None:
            return None

        @staticmethod
        def drop_column(*args, **kwargs) -> None:
            return None

        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

        @staticmethod
        def get_bind():
            return fake_bind

    migration.op = FakeOp()

    migration.downgrade()

    assert not any(
        "ALTER PUBLICATION supabase_realtime DROP TABLE website_processing_jobs"
        in statement
        for statement in executed_sql
    )
