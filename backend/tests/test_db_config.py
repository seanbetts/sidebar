"""Tests for test database selection helpers."""

from tests.db_config import (
    LOCAL_TEST_DATABASE_URL,
    is_supabase_database_url,
    is_truthy,
    resolve_default_test_database_url,
    use_supabase_test_db,
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
