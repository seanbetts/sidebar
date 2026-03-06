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
        / "20260306_1200-057_add_semantic_note_document.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_057_add_semantic_note_document",
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
    assert columns["document"].nullable is True
    assert columns["content"].nullable is False
    assert columns["content_format"].nullable is False
    assert columns["plain_text"].nullable is False
    assert columns["title"].nullable is False


def test_semantic_note_document_migration_adds_transitional_columns() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert any(
        "ADD COLUMN IF NOT EXISTS document jsonb" in statement
        for statement in executed_sql
    )
    assert any(
        "ADD COLUMN IF NOT EXISTS document_version integer NOT NULL DEFAULT 1"
        in statement
        for statement in executed_sql
    )
    assert not any("DROP COLUMN IF EXISTS content" in statement for statement in executed_sql)
    assert not any(
        "DROP COLUMN IF EXISTS content_format" in statement for statement in executed_sql
    )
