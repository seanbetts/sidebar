"""Tests for the Fly production migration entrypoint."""

from __future__ import annotations

import os
from urllib.parse import unquote, urlsplit

import pytest

from scripts import run_production_migrations


def test_main_supplies_owner_url_and_upgrades_the_single_head(monkeypatch) -> None:
    """The release entrypoint must hand the owner connection to Alembic."""
    environment = {
        "SUPABASE_PROJECT_ID": "project-ref",
        "SUPABASE_POOLER_HOST": "pooler.example.com",
        "SUPABASE_POOLER_PORT": "5432",
        "SUPABASE_DB_NAME": "postgres",
        "SUPABASE_SSLMODE": "require",
        "SUPABASE_POSTGRES_PSWD": "admin-secret",
    }
    for name, value in environment.items():
        monkeypatch.setenv(name, value)
    monkeypatch.delenv("DATABASE_URL_DIRECT", raising=False)
    observed: dict[str, str] = {}

    def record_upgrade(config, target: str) -> None:
        observed["target"] = target
        observed["database_url"] = os.environ["DATABASE_URL_DIRECT"]
        observed["script_location"] = config.get_main_option("script_location")

    monkeypatch.setattr(run_production_migrations.command, "upgrade", record_upgrade)

    run_production_migrations.main()

    assert observed["target"] == "head"
    assert urlsplit(observed["database_url"]).username == "postgres.project-ref"
    assert observed["script_location"] == str(
        run_production_migrations.BACKEND_ROOT / "api" / "alembic"
    )


def test_migration_url_uses_postgres_role_and_not_runtime_app_credentials() -> None:
    """Schema changes must not run through the restricted sidebar_app role."""
    url = run_production_migrations.build_migration_database_url(
        {
            "SUPABASE_PROJECT_ID": "project-ref",
            "SUPABASE_POOLER_HOST": "pooler.example.com",
            "SUPABASE_POOLER_PORT": "5432",
            "SUPABASE_DB_NAME": "postgres",
            "SUPABASE_SSLMODE": "require",
            "SUPABASE_POSTGRES_PSWD": "admin p@ss/word",
            "SUPABASE_APP_PSWD": "runtime-secret",
            "SUPABASE_POOLER_USER": "sidebar_app.project-ref",
        }
    )

    parsed = urlsplit(url)
    assert unquote(parsed.username or "") == "postgres.project-ref"
    assert unquote(parsed.password or "") == "admin p@ss/word"
    assert parsed.hostname == "pooler.example.com"
    assert parsed.port == 5432
    assert parsed.path == "/postgres"
    assert parsed.query == "sslmode=require"
    assert "runtime-secret" not in url
    assert "sidebar_app" not in url


@pytest.mark.parametrize(
    "missing_name",
    [
        "SUPABASE_PROJECT_ID",
        "SUPABASE_POOLER_HOST",
        "SUPABASE_POSTGRES_PSWD",
    ],
)
def test_migration_url_fails_closed_when_admin_configuration_is_missing(
    missing_name: str,
) -> None:
    """A partial secret/config deployment must stop before Alembic connects."""
    environment = {
        "SUPABASE_PROJECT_ID": "project-ref",
        "SUPABASE_POOLER_HOST": "pooler.example.com",
        "SUPABASE_POSTGRES_PSWD": "admin-secret",
    }
    environment.pop(missing_name)

    with pytest.raises(RuntimeError, match=missing_name):
        run_production_migrations.build_migration_database_url(environment)
