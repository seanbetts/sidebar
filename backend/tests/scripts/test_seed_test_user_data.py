"""Tests for backend/scripts/seed_test_user_data.py."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from scripts.seed_test_user_data import (
    assert_safe_environment,
    parse_args,
    parse_now,
)


def test_parse_now_accepts_z_suffix() -> None:
    parsed = parse_now("2026-02-09T00:00:00Z")
    assert parsed == datetime(2026, 2, 9, 0, 0, tzinfo=UTC)


def test_parse_now_rejects_invalid_value() -> None:
    with pytest.raises(ValueError):
        parse_now("not-a-timestamp")


def test_parse_args_rejects_delete_and_reset_together() -> None:
    with pytest.raises(SystemExit):
        parse_args(["--user-id", "123e4567-e89b-12d3-a456-426614174000", "--delete", "--reset"])


def test_assert_safe_environment_blocks_production(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv(
        "DATABASE_URL", "postgresql://user:pass@db.example.com:5432/postgres"
    )

    with pytest.raises(RuntimeError, match="Refusing to run seed script"):
        assert_safe_environment(allow_production=False)


def test_assert_safe_environment_allows_override(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("APP_ENV", "production")
    assert_safe_environment(allow_production=True)
