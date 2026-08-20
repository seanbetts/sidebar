#!/usr/bin/env python3
"""Run Alembic with the production schema-owner credential."""

from __future__ import annotations

import os
from collections.abc import Mapping
from pathlib import Path
from urllib.parse import quote, urlencode

from alembic import command
from alembic.config import Config


BACKEND_ROOT = Path(__file__).resolve().parents[1]
REQUIRED_SETTINGS = (
    "SUPABASE_PROJECT_ID",
    "SUPABASE_POOLER_HOST",
    "SUPABASE_POSTGRES_PSWD",
)


def build_migration_database_url(environment: Mapping[str, str]) -> str:
    """Build a session-pooler URL for the schema-owning Postgres role."""
    missing = [name for name in REQUIRED_SETTINGS if not environment.get(name)]
    if missing:
        raise RuntimeError(
            "Missing production migration configuration: " + ", ".join(missing)
        )

    project_id = environment["SUPABASE_PROJECT_ID"]
    host = environment["SUPABASE_POOLER_HOST"]
    password = environment["SUPABASE_POSTGRES_PSWD"]
    port = _validated_port(environment.get("SUPABASE_POOLER_PORT", "5432"))
    database = environment.get("SUPABASE_DB_NAME", "postgres")
    sslmode = environment.get("SUPABASE_SSLMODE", "require")
    username = f"postgres.{project_id}"

    return (
        f"postgresql://{quote(username, safe='')}:{quote(password, safe='')}"
        f"@{host}:{port}/{quote(database, safe='')}?"
        f"{urlencode({'sslmode': sslmode})}"
    )


def main() -> None:
    """Upgrade production to the sole Alembic head before Fly rolls Machines."""
    os.environ["DATABASE_URL_DIRECT"] = build_migration_database_url(os.environ)
    config = Config(str(BACKEND_ROOT / "api" / "alembic.ini"))
    config.set_main_option("script_location", str(BACKEND_ROOT / "api" / "alembic"))
    command.upgrade(config, "head")


def _validated_port(raw_port: str) -> int:
    try:
        port = int(raw_port)
    except ValueError as exc:
        raise RuntimeError("Invalid SUPABASE_POOLER_PORT") from exc
    if not 1 <= port <= 65535:
        raise RuntimeError("Invalid SUPABASE_POOLER_PORT")
    return port


if __name__ == "__main__":
    main()
