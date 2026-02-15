"""Helpers for selecting the test database URL."""

from __future__ import annotations

from typing import Mapping
from urllib.parse import urlparse

LOCAL_TEST_DATABASE_URL = "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test"
_TRUTHY_VALUES = {"1", "true", "yes", "on"}


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
