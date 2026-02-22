"""Tests for 055 reclassified-store-skill prune migration helpers."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260222_1100-055_prune_reclassified_store_skills.py"
    )
    spec = importlib.util.spec_from_file_location(
        "migration_055_prune_reclassified_store_skills",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_normalize_installed_store_skills_prunes_reclassified_ids() -> None:
    migration = _load_migration_module()

    normalized = migration._normalize_installed_store_skills(
        [
            "audio-transcribe",
            "prompt-preview",
            "settings-other-preferences",
            "youtube-download",
        ]
    )

    assert normalized == ["audio-transcribe", "youtube-download"]


def test_normalize_installed_store_skills_deduplicates_and_trims() -> None:
    migration = _load_migration_module()

    normalized = migration._normalize_installed_store_skills(
        [
            " audio-transcribe ",
            "audio-transcribe",
            "",
            "youtube-transcribe",
            "youtube-transcribe",
        ]
    )

    assert normalized == ["audio-transcribe", "youtube-transcribe"]


def test_normalize_installed_store_skills_handles_invalid_payload() -> None:
    migration = _load_migration_module()

    assert migration._normalize_installed_store_skills(None) == []
    assert migration._normalize_installed_store_skills("audio-transcribe") == []
