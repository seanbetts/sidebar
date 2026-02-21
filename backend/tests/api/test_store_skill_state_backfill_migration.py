"""Tests for 054 store skill state backfill migration helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260221_0900-054_backfill_store_skill_state.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_054_backfill_store_skill_state",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_normalize_row_state_preserves_pre_cutover_null_behavior() -> None:
    migration = _load_migration_module()

    enabled, installed = migration._normalize_row_state(None, None)

    assert enabled == migration.EXPOSED_SKILL_IDS
    assert installed == [
        skill for skill in migration.EXPOSED_SKILL_IDS if skill in migration.STORE_SKILL_IDS
    ]


def test_normalize_row_state_backfills_installed_from_enabled_and_canonicalizes() -> None:
    migration = _load_migration_module()

    enabled, installed = migration._normalize_row_state(
        ["fs", "audio-transcribe", "files", "not-a-skill"],
        None,
    )

    assert enabled == [
        "files",
        "audio-transcribe",
        "assistant-identity",
        "assistant-soul",
    ]
    assert installed == ["audio-transcribe"]


def test_normalize_row_state_uses_existing_installed_list_when_present() -> None:
    migration = _load_migration_module()

    enabled, installed = migration._normalize_row_state(
        ["files"],
        ["youtube-transcribe", "files", "fs", "audio-transcribe"],
    )

    assert enabled == ["files", "assistant-identity", "assistant-soul"]
    assert installed == ["youtube-transcribe", "audio-transcribe"]
