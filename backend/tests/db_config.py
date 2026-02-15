"""Helpers for selecting the test database URL."""

from __future__ import annotations

from typing import Mapping
from urllib.parse import urlparse

LOCAL_TEST_DATABASE_URL = "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test"
_TRUTHY_VALUES = {"1", "true", "yes", "on"}
_PLACEHOLDER_SUBSTRINGS = {
    "test-",
    "example",
    "changeme",
    "placeholder",
    "dummy",
}


def is_truthy(value: str | None) -> bool:
    """Return whether a string value should be treated as true."""
    if value is None:
        return False
    return value.strip().lower() in _TRUTHY_VALUES


def use_supabase_test_db(env: Mapping[str, str]) -> bool:
    """Return whether hosted Supabase DB should be used for tests."""
    return is_truthy(env.get("USE_SUPABASE_TEST_DB"))


def is_supabase_database_url(database_url: str | None) -> bool:
    """Return whether a database URL points to a Supabase host."""
    if not database_url:
        return False
    hostname = (urlparse(database_url).hostname or "").lower()
    return "supabase.co" in hostname or "pooler.supabase.com" in hostname


def resolve_default_test_database_url(env: Mapping[str, str]) -> str:
    """Resolve a safe default DB URL for local test runs."""
    configured_url = (env.get("DATABASE_URL") or "").strip()
    if not configured_url:
        return LOCAL_TEST_DATABASE_URL
    if not use_supabase_test_db(env) and is_supabase_database_url(configured_url):
        return LOCAL_TEST_DATABASE_URL
    return configured_url


def is_placeholder_value(value: str | None) -> bool:
    """Return whether a value appears to be a placeholder secret."""
    if value is None:
        return True
    normalized = value.strip().lower()
    if not normalized:
        return True
    return any(marker in normalized for marker in _PLACEHOLDER_SUBSTRINGS)


def validate_supabase_test_env(env: Mapping[str, str]) -> list[str]:
    """Validate hosted Supabase test lane configuration.

    Returns:
        List of human-readable validation errors. Empty when config looks usable.
    """
    errors: list[str] = []

    configured_url = (env.get("DATABASE_URL") or "").strip()
    if configured_url and is_supabase_database_url(configured_url):
        parsed = urlparse(configured_url)
        if not parsed.hostname:
            errors.append("DATABASE_URL is missing a hostname.")
        if not parsed.username:
            errors.append("DATABASE_URL is missing a username.")
        if is_placeholder_value(parsed.password):
            errors.append("DATABASE_URL password appears to be a placeholder.")
        return errors

    supabase_url = (env.get("SUPABASE_URL") or "").strip()
    project_id = (env.get("SUPABASE_PROJECT_ID") or "").strip()
    pooler_host = (env.get("SUPABASE_POOLER_HOST") or "").strip()
    pooler_user = (env.get("SUPABASE_POOLER_USER") or "").strip()
    db_password = (env.get("SUPABASE_APP_PSWD") or env.get("SUPABASE_POSTGRES_PSWD") or "").strip()

    if not supabase_url or "supabase.co" not in supabase_url:
        errors.append("SUPABASE_URL must be set to a valid Supabase project URL.")
    if not project_id:
        errors.append("SUPABASE_PROJECT_ID must be set.")
    if not pooler_host or "pooler.supabase.com" not in pooler_host:
        errors.append("SUPABASE_POOLER_HOST must be set to a Supabase pooler host.")
    if not pooler_user:
        errors.append("SUPABASE_POOLER_USER must be set.")
    if is_placeholder_value(db_password):
        errors.append(
            "SUPABASE_APP_PSWD or SUPABASE_POSTGRES_PSWD must be set to a non-placeholder value."
        )

    return errors
