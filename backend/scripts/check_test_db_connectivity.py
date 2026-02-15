#!/usr/bin/env python3
"""Preflight check for backend test DB lanes."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import urlparse

from sqlalchemy import create_engine, text

# Ensure backend package roots (including tests/) are importable when run as a script.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from tests.db_config import (  # noqa: E402
    build_supabase_test_database_url,
    resolve_default_test_database_url,
    use_supabase_test_db,
    validate_supabase_test_env,
)


def _masked_url_summary(database_url: str) -> str:
    parsed = urlparse(database_url)
    host = parsed.hostname or "unknown"
    port = parsed.port or "unknown"
    database = (parsed.path or "/").lstrip("/") or "unknown"
    user = parsed.username or "unknown"
    return f"user={user} host={host} port={port} db={database}"


def _load_env_file(
    env: dict[str, str],
    path: Path,
    allowed_prefixes: tuple[str, ...] | None = None,
    *,
    override: bool = False,
) -> None:
    if not path.exists():
        return

    for line in path.read_text().splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if allowed_prefixes and not key.startswith(allowed_prefixes):
            continue
        if override or key not in env:
            env[key] = value.strip()


def main() -> int:
    env = dict(os.environ)
    env_test_path = BACKEND_ROOT / ".env.test"
    _load_env_file(env, env_test_path)

    hosted_lane = use_supabase_test_db(env)
    if hosted_lane:
        _load_env_file(
            env,
            env_test_path,
            allowed_prefixes=("SUPABASE_", "DATABASE_URL"),
            override=True,
        )

    lane_name = "hosted Supabase lane" if hosted_lane else "local default lane"

    database_url = (
        build_supabase_test_database_url(env)
        if hosted_lane
        else resolve_default_test_database_url(env)
    )
    if not database_url:
        print("DB preflight failed: unable to resolve database URL from test environment.")
        return 2

    print(f"Test DB lane: {lane_name}")
    print(f"Resolved DB target: {_masked_url_summary(database_url)}")

    if hosted_lane:
        errors = validate_supabase_test_env(env)
        if errors:
            print("Hosted Supabase lane config is invalid:")
            for error in errors:
                print(f"  - {error}")
            return 2

    try:
        engine = create_engine(database_url, pool_pre_ping=True)
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except Exception as exc:
        print(f"DB preflight failed: {exc}")
        return 1
    finally:
        if "engine" in locals():
            engine.dispose()

    print("DB preflight passed (SELECT 1).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
