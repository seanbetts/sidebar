"""Tests for semantic note document schema support."""

from __future__ import annotations

import importlib.util
from pathlib import Path

from api.models.note import Note


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260306_1800-058_drop_legacy_note_rtf_columns.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_058_drop_legacy_note_rtf_columns",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_note_model_includes_semantic_document_columns() -> None:
    columns = Note.__table__.columns

    assert "document" in columns
    assert "document_version" in columns
    assert columns["document"].nullable is False
    assert "content" not in columns
    assert "content_format" not in columns
    assert columns["plain_text"].nullable is False
    assert columns["title"].nullable is False


def test_semantic_note_document_cleanup_migration_drops_legacy_columns() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert any(
        "UPDATE notes" in statement and "jsonb_build_object" in statement
        for statement in executed_sql
    )
    assert any(
        "ALTER TABLE notes ALTER COLUMN document SET NOT NULL" in statement
        for statement in executed_sql
    )
    assert any(
        "DROP COLUMN IF EXISTS content" in statement for statement in executed_sql
    )
    assert any(
        "DROP COLUMN IF EXISTS content_format" in statement
        for statement in executed_sql
    )
