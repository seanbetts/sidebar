#!/usr/bin/env python3
"""Preflight check for backend test DB lanes."""

from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from sqlalchemy import create_engine, text

# Ensure backend package roots (including tests/) are importable when run as a script.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from tests.db_config import (  # noqa: E402
    build_supabase_test_database_url,
    is_placeholder_value,
    resolve_default_test_database_url,
    use_supabase_test_db,
    validate_supabase_test_env,
)

LOCAL_SETUP_CMD = "./scripts/setup_test_db.sh"
HOSTED_MIGRATE_CMD = "USE_SUPABASE_TEST_DB=1 UV_NATIVE_TLS=1 uv run alembic -c api/alembic.ini upgrade head"


@dataclass(frozen=True)
class MigrationBaselineState:
    """Schema/alembic_version snapshot used for preflight validation."""

    non_alembic_table_count: int
    alembic_version_row_count: int


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


def _doppler_env(env: dict[str, str]) -> dict[str, str]:
    """Return subprocess env with Doppler context variables populated."""
    proc_env = dict(os.environ)
    for key in ("DOPPLER_TOKEN", "DOPPLER_PROJECT", "DOPPLER_CONFIG"):
        value = env.get(key)
        if value:
            proc_env[key] = value
    return proc_env


def _read_doppler_secret(name: str, env: dict[str, str]) -> str:
    """Best-effort read of a Doppler secret."""
    try:
        return subprocess.check_output(
            ["doppler", "secrets", "get", name, "--plain"],
            text=True,
            env=_doppler_env(env),
        ).strip()
    except Exception:
        return ""


def _hydrate_supabase_password_from_doppler(env: dict[str, str]) -> None:
    """Populate hosted test DB password from Doppler when placeholders are present."""
    if not env.get("DOPPLER_TOKEN"):
        return

    postgres_password = (env.get("SUPABASE_POSTGRES_PSWD") or "").strip()
    if not is_placeholder_value(postgres_password):
        return

    legacy_app_password = (env.get("SUPABASE_APP_PSWD") or "").strip()
    if not is_placeholder_value(legacy_app_password):
        env["SUPABASE_POSTGRES_PSWD"] = legacy_app_password
        return

    for key in ("SUPABASE_POSTGRES_TEST_PSWD", "SUPABASE_POSTGRES_PSWD", "SUPABASE_APP_PSWD"):
        value = _read_doppler_secret(key, env)
        if not is_placeholder_value(value):
            env["SUPABASE_POSTGRES_PSWD"] = value
            break


def _collect_migration_baseline_state(connection) -> MigrationBaselineState:
    """Return counts needed to validate the Alembic baseline."""
    alembic_exists = bool(
        connection.execute(
            text("SELECT to_regclass('public.alembic_version') IS NOT NULL")
        ).scalar_one()
    )

    public_table_count = int(
        connection.execute(
            text(
                "SELECT COUNT(*) "
                "FROM information_schema.tables "
                "WHERE table_schema = 'public' "
                "AND table_type = 'BASE TABLE'"
            )
        ).scalar_one()
    )

    alembic_version_row_count = 0
    if alembic_exists:
        alembic_version_row_count = int(
            connection.execute(text("SELECT COUNT(*) FROM alembic_version")).scalar_one()
        )

    non_alembic_table_count = public_table_count - (1 if alembic_exists else 0)
    return MigrationBaselineState(
        non_alembic_table_count=max(non_alembic_table_count, 0),
        alembic_version_row_count=alembic_version_row_count,
    )


def _validate_migration_baseline(state: MigrationBaselineState, *, hosted_lane: bool) -> str | None:
    """Return an actionable error message when schema/alembic state is invalid."""
    recovery_cmd = HOSTED_MIGRATE_CMD if hosted_lane else LOCAL_SETUP_CMD

    if state.alembic_version_row_count > 1:
        return (
            "DB preflight failed: alembic_version has multiple rows.\n"
            "Repair guidance: reset the test DB and reapply migrations.\n"
            f"  {recovery_cmd}"
        )

    if state.alembic_version_row_count == 0 and state.non_alembic_table_count == 0:
        return (
            "DB preflight failed: test DB schema is empty and no Alembic baseline is set.\n"
            "Initialize schema with Alembic before running tests.\n"
            f"  {recovery_cmd}"
        )

    if state.alembic_version_row_count == 0 and state.non_alembic_table_count > 0:
        return (
            "DB preflight failed: schema tables exist but alembic_version is empty.\n"
            "This environment is not migration-baselined and will fail on future upgrades.\n"
            "Recreate or repair the test DB using:\n"
            f"  {recovery_cmd}"
        )

    if state.alembic_version_row_count >= 1 and state.non_alembic_table_count == 0:
        return (
            "DB preflight failed: alembic_version is stamped but application tables are missing.\n"
            "Reset and migrate the test DB to restore a consistent baseline:\n"
            f"  {recovery_cmd}"
        )

    return None


def main() -> int:
    env = dict(os.environ)
    env_test_path = BACKEND_ROOT / ".env.test"
    env_local_path = BACKEND_ROOT.parent / ".env.local"
    _load_env_file(env, env_test_path)
    _load_env_file(env, env_local_path, allowed_prefixes=("DOPPLER_",))

    hosted_lane = use_supabase_test_db(env)
    if hosted_lane:
        _load_env_file(
            env,
            env_test_path,
            allowed_prefixes=("SUPABASE_", "DATABASE_URL"),
            override=True,
        )
        _hydrate_supabase_password_from_doppler(env)

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
            state = _collect_migration_baseline_state(connection)
            baseline_error = _validate_migration_baseline(state, hosted_lane=hosted_lane)
            if baseline_error:
                print(baseline_error)
                return 1
    except Exception as exc:
        print(f"DB preflight failed: {exc}")
        return 1
    finally:
        if "engine" in locals():
            engine.dispose()

    print("DB preflight passed (SELECT 1 + Alembic baseline check).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
