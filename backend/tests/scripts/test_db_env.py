"""Tests for backend/scripts/db_env.py."""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse

import pytest

from scripts.db_env import _build_pooler_database_url


@pytest.fixture(autouse=True)
def _clear_supabase_env(monkeypatch: pytest.MonkeyPatch) -> None:
    keys = (
        "SUPABASE_POOLER_URL",
        "SUPABASE_POOLER_HOST",
        "SUPABASE_POOLER_USER",
        "SUPABASE_POOLER_PORT",
        "SUPABASE_POOLER_MODE",
        "SUPABASE_DB_NAME",
        "SUPABASE_SSLMODE",
        "SUPABASE_APP_PSWD",
        "SUPABASE_POSTGRES_PSWD",
    )
    for key in keys:
        monkeypatch.delenv(key, raising=False)


def test_build_pooler_database_url_prefers_pooler_url_identity(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv(
        "SUPABASE_POOLER_URL",
        (
            "postgresql://postgres.your-supabase-project-ref@"
            "aws-1-eu-central-1.pooler.supabase.com:5432/postgres"
        ),
    )
    monkeypatch.setenv(
        "SUPABASE_POOLER_USER",
        "sidebar_app.your-supabase-project-ref",
    )
    monkeypatch.setenv("SUPABASE_POSTGRES_PSWD", "secret-password")

    url = _build_pooler_database_url()

    assert url is not None
    parsed = urlparse(url)
    assert parsed.hostname == "aws-1-eu-central-1.pooler.supabase.com"
    assert parsed.username == "postgres.your-supabase-project-ref"
    assert parsed.port == 6543


def test_build_pooler_database_url_uses_env_user_when_pooler_url_has_none(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv(
        "SUPABASE_POOLER_URL",
        "postgresql://aws-1-eu-central-1.pooler.supabase.com:5432/postgres",
    )
    monkeypatch.setenv(
        "SUPABASE_POOLER_USER",
        "sidebar_app.your-supabase-project-ref",
    )
    monkeypatch.setenv("SUPABASE_APP_PSWD", "secret-password")
    monkeypatch.setenv("SUPABASE_POOLER_MODE", "session")
    monkeypatch.setenv("SUPABASE_POOLER_PORT", "5432")
    monkeypatch.setenv("SUPABASE_SSLMODE", "require")

    url = _build_pooler_database_url()

    assert url is not None
    parsed = urlparse(url)
    assert parsed.hostname == "aws-1-eu-central-1.pooler.supabase.com"
    assert parsed.username == "sidebar_app.your-supabase-project-ref"
    assert parsed.port == 5432
    assert parse_qs(parsed.query)["sslmode"] == ["require"]
