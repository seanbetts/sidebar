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
    added_columns: list[tuple[str, str]] = []

    class FakeOp:
        @staticmethod
        def add_column(table_name, column) -> None:
            added_columns.append((table_name, column.name))

        @staticmethod
        def create_index(*_args, **_kwargs) -> None:
            return None

        @staticmethod
        def drop_index(*_args, **_kwargs) -> None:
            return None

        @staticmethod
        def drop_column(*_args, **_kwargs) -> None:
            return None

        @staticmethod
        def execute(*_args, **_kwargs) -> None:
            return None

    migration.op = FakeOp()

    migration.upgrade()

    assert ("notes", "payload_purged_at") in added_columns
    assert ("websites", "payload_purged_at") in added_columns


def test_upgrade_creates_cleanup_indexes_for_operational_pruning() -> None:
    migration = _load_migration_module()
    created_indexes: list[tuple[str, str]] = []

    class FakeOp:
        @staticmethod
        def add_column(*_args, **_kwargs) -> None:
            return None

        @staticmethod
        def create_index(name, table_name, *_args, **_kwargs) -> None:
            created_indexes.append((name, table_name))

        @staticmethod
        def execute(*_args, **_kwargs) -> None:
            return None

    migration.op = FakeOp()

    migration.upgrade()

    assert ("idx_website_jobs_updated_at", "website_processing_jobs") in created_indexes
