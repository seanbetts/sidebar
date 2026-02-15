"""Tests for test database selection helpers."""

from tests.db_config import (
    LOCAL_TEST_DATABASE_URL,
    build_supabase_test_database_url,
    is_supabase_database_url,
    is_placeholder_value,
    is_truthy,
    resolve_supabase_db_password,
    resolve_default_test_database_url,
    use_supabase_test_db,
    validate_supabase_test_env,
)


def test_is_truthy_handles_common_true_values() -> None:
    assert is_truthy("1")
    assert is_truthy("true")
    assert is_truthy("YES")
    assert is_truthy(" on ")


def test_is_truthy_rejects_falsey_values() -> None:
    assert not is_truthy(None)
    assert not is_truthy("")
    assert not is_truthy("0")
    assert not is_truthy("false")


def test_use_supabase_test_db_reads_opt_in_flag() -> None:
    assert use_supabase_test_db({"USE_SUPABASE_TEST_DB": "1"})
    assert not use_supabase_test_db({})


def test_is_supabase_database_url_detects_pooler_and_direct_hosts() -> None:
    assert is_supabase_database_url(
        "postgresql://user:pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres"
    )
    assert is_supabase_database_url(
        "postgresql://postgres:pass@db.projectid.supabase.co:5432/postgres"
    )
    assert not is_supabase_database_url(
        "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test"
    )


def test_resolve_default_uses_local_when_database_url_is_missing() -> None:
    assert resolve_default_test_database_url({}) == LOCAL_TEST_DATABASE_URL


def test_resolve_default_overrides_supabase_url_without_opt_in() -> None:
    env = {
        "DATABASE_URL": "postgresql://user:pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres"
    }
    assert resolve_default_test_database_url(env) == LOCAL_TEST_DATABASE_URL


def test_resolve_default_keeps_supabase_url_with_opt_in() -> None:
    env = {
        "USE_SUPABASE_TEST_DB": "true",
        "DATABASE_URL": "postgresql://user:pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres",
    }
    assert resolve_default_test_database_url(env) == env["DATABASE_URL"]


def test_resolve_default_keeps_non_supabase_custom_url() -> None:
    env = {"DATABASE_URL": "postgresql://tester:pass@127.0.0.1:15432/sidebar_test"}
    assert resolve_default_test_database_url(env) == env["DATABASE_URL"]


def test_is_placeholder_value_detects_common_test_values() -> None:
    assert is_placeholder_value("test-password")
    assert is_placeholder_value("example-secret")
    assert not is_placeholder_value("real-secret-value")


def test_resolve_supabase_db_password_prefers_postgres_secret() -> None:
    env = {
        "SUPABASE_POSTGRES_PSWD": "postgres-secret",
        "SUPABASE_APP_PSWD": "app-secret",
    }
    assert resolve_supabase_db_password(env) == "postgres-secret"


def test_resolve_supabase_db_password_falls_back_to_legacy_app_secret() -> None:
    env = {
        "SUPABASE_POSTGRES_PSWD": "test-password",
        "SUPABASE_APP_PSWD": "app-secret",
    }
    assert resolve_supabase_db_password(env) == "app-secret"


def test_validate_supabase_test_env_accepts_supabase_database_url() -> None:
    env = {
        "DATABASE_URL": "postgresql://postgres.real:secure-pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres"
    }
    assert validate_supabase_test_env(env) == []


def test_validate_supabase_test_env_rejects_placeholder_database_url_password() -> None:
    env = {
        "DATABASE_URL": "postgresql://postgres.real:test-password@aws-1-eu-west-1.pooler.supabase.com:6543/postgres"
    }
    errors = validate_supabase_test_env(env)
    assert errors
    assert "DATABASE_URL password appears to be a placeholder." in errors


def test_validate_supabase_test_env_requires_non_placeholder_supabase_settings() -> None:
    env = {
        "SUPABASE_URL": "https://project.supabase.co",
        "SUPABASE_PROJECT_ID": "project",
        "SUPABASE_POOLER_HOST": "aws-1-eu-west-1.pooler.supabase.com",
        "SUPABASE_POOLER_USER": "postgres.project",
        "SUPABASE_POSTGRES_PSWD": "test-placeholder-password",
    }
    errors = validate_supabase_test_env(env)
    assert errors
    assert any("must be non-placeholder" in message for message in errors)


def test_validate_supabase_test_env_accepts_legacy_app_password_fallback() -> None:
    env = {
        "SUPABASE_URL": "https://project.supabase.co",
        "SUPABASE_PROJECT_ID": "project",
        "SUPABASE_POOLER_HOST": "aws-1-eu-west-1.pooler.supabase.com",
        "SUPABASE_POOLER_USER": "sidebar_app.project",
        "SUPABASE_POSTGRES_PSWD": "test-placeholder-password",
        "SUPABASE_APP_PSWD": "secure pass",
    }
    assert validate_supabase_test_env(env) == []


def test_build_supabase_test_database_url_uses_supabase_database_url() -> None:
    env = {
        "DATABASE_URL": "postgresql://postgres.real:secure-pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres"
    }
    assert build_supabase_test_database_url(env) == env["DATABASE_URL"]


def test_build_supabase_test_database_url_builds_from_pooler_env() -> None:
    env = {
        "SUPABASE_POOLER_HOST": "aws-1-eu-west-1.pooler.supabase.com",
        "SUPABASE_POOLER_USER": "sidebar_app.project",
        "SUPABASE_APP_PSWD": "secure pass",
        "SUPABASE_DB_NAME": "postgres",
        "SUPABASE_SSLMODE": "require",
    }
    assert (
        build_supabase_test_database_url(env)
        == "postgresql://sidebar_app.project:secure+pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres?sslmode=require"
    )


def test_build_supabase_test_database_url_prefers_postgres_password() -> None:
    env = {
        "SUPABASE_POOLER_HOST": "aws-1-eu-west-1.pooler.supabase.com",
        "SUPABASE_POOLER_USER": "sidebar_app.project",
        "SUPABASE_POSTGRES_PSWD": "postgres pass",
        "SUPABASE_APP_PSWD": "app pass",
        "SUPABASE_DB_NAME": "postgres",
        "SUPABASE_SSLMODE": "require",
    }
    assert (
        build_supabase_test_database_url(env)
        == "postgresql://sidebar_app.project:postgres+pass@aws-1-eu-west-1.pooler.supabase.com:6543/postgres?sslmode=require"
    )
