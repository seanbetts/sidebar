"""Tests for 059 user skill state migration helpers."""

from __future__ import annotations

import importlib.util
from datetime import UTC, datetime
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260307_1500-059_add_user_skill_states.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_059_add_user_skill_states",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_normalize_row_state_backfills_installed_store_skills_into_defaults() -> None:
    migration = _load_migration_module()

    enabled, installed = migration._normalize_row_state(
        None,
        [" audio-transcribe ", "audio-transcribe", "files"],
    )

    assert enabled == migration.DEFAULT_ENABLED_SKILL_IDS + ["audio-transcribe"]
    assert installed == ["audio-transcribe"]


def test_normalize_row_state_infers_installed_skills_from_enabled_when_missing() -> None:
    migration = _load_migration_module()

    enabled, installed = migration._normalize_row_state(
        ["files", "audio-transcribe", "youtube-download", "not-a-skill"],
        None,
    )

    assert enabled == [
        "files",
        "audio-transcribe",
        "youtube-download",
        "assistant-identity",
        "assistant-soul",
        "product-feedback",
    ]
    assert installed == ["audio-transcribe", "youtube-download"]


def test_build_user_skill_state_rows_marks_store_install_state() -> None:
    migration = _load_migration_module()
    created_at = datetime(2026, 3, 7, 15, 0, tzinfo=UTC)
    updated_at = datetime(2026, 3, 7, 16, 0, tzinfo=UTC)

    rows = migration._build_user_skill_state_rows(
        user_id="migration-user",
        raw_enabled=["files", "audio-transcribe"],
        raw_installed=["audio-transcribe"],
        created_at=created_at,
        updated_at=updated_at,
    )

    by_skill = {row["skill_id"]: row for row in rows}
    assert by_skill["files"]["enabled"] is True
    assert by_skill["files"]["installed"] is False
    assert by_skill["audio-transcribe"]["enabled"] is True
    assert by_skill["audio-transcribe"]["installed"] is True
    assert by_skill["assistant-identity"]["enabled"] is True
    assert by_skill["assistant-soul"]["enabled"] is True
    assert by_skill["product-feedback"]["enabled"] is True
    assert all(row["user_id"] == "migration-user" for row in rows)
    assert all(row["created_at"] == created_at for row in rows)
    assert all(row["updated_at"] == updated_at for row in rows)
