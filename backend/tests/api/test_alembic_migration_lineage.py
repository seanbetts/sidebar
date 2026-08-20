"""Integration coverage for the production Alembic migration lineage."""

from __future__ import annotations

import os
import subprocess
import sys
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

import psycopg2
from alembic.config import Config
from alembic.script import ScriptDirectory
from psycopg2 import sql


BACKEND_ROOT = Path(__file__).resolve().parents[2]
ALEMBIC_CONFIG_PATH = BACKEND_ROOT / "api" / "alembic.ini"
MERGED_HEAD = "080_merge_live_notes_and_task_reminders"
PRODUCTION_BASELINE = "079_add_rls_to_live_note_sessions"


def test_migration_graph_has_one_head_covering_both_production_branches() -> None:
    """Deploys must not leave live-notes and task reminders on separate heads."""
    config = Config(str(ALEMBIC_CONFIG_PATH))
    config.set_main_option("path_separator", "os")
    config.set_main_option("script_location", str(BACKEND_ROOT / "api" / "alembic"))
    scripts = ScriptDirectory.from_config(config)

    assert scripts.get_heads() == [MERGED_HEAD]
    merged = scripts.get_revision(MERGED_HEAD)
    assert merged is not None
    assert isinstance(merged.down_revision, tuple)
    assert set(merged.down_revision) == {
        PRODUCTION_BASELINE,
        "078_add_task_reminder_delivery_states",
    }


def test_production_live_notes_revision_upgrades_to_merged_schema() -> None:
    """The deployed 079 lineage must gain reminder state without losing live notes."""
    with _temporary_database() as database_url:
        _run_alembic(database_url, "upgrade", PRODUCTION_BASELINE)

        with psycopg2.connect(database_url) as connection:
            assert _table_exists(connection, "live_note_sessions")
            assert not _table_exists(connection, "task_reminder_delivery_states")
            assert _alembic_versions(connection) == {PRODUCTION_BASELINE}

        _run_alembic(database_url, "upgrade", "head")

        with psycopg2.connect(database_url) as connection:
            assert _table_exists(connection, "live_note_sessions")
            assert _table_exists(connection, "task_reminder_delivery_states")
            assert _alembic_versions(connection) == {MERGED_HEAD}
            assert _row_security_enabled(
                connection,
                "task_reminder_delivery_states",
            )
            assert _table_policies(connection, "task_reminder_delivery_states") == {
                "task_reminder_delivery_states_user_operations",
                "task_reminder_delivery_states_worker_select",
            }
            assert _client_grantees(connection, "task_reminder_delivery_states") == set()


@contextmanager
def _temporary_database() -> Iterator[str]:
    source_url = os.environ["DATABASE_URL"]
    parsed = urlsplit(source_url)
    database_name = f"sidebar_migration_{uuid.uuid4().hex}"
    admin_url = urlunsplit(parsed._replace(path="/postgres"))
    database_url = urlunsplit(parsed._replace(path=f"/{database_name}"))

    admin_connection = psycopg2.connect(admin_url)
    admin_connection.autocommit = True
    try:
        with admin_connection.cursor() as cursor:
            cursor.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database_name)))
        with psycopg2.connect(database_url) as connection:
            with connection.cursor() as cursor:
                cursor.execute("CREATE SCHEMA IF NOT EXISTS auth")
                cursor.execute(
                    """
                    CREATE OR REPLACE FUNCTION auth.uid()
                    RETURNS uuid
                    LANGUAGE sql
                    STABLE
                    AS $$
                      SELECT NULLIF(
                        current_setting('request.jwt.claim.sub', true),
                        ''
                      )::uuid
                    $$
                    """
                )
        yield database_url
    finally:
        with admin_connection.cursor() as cursor:
            cursor.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                "WHERE datname = %s AND pid <> pg_backend_pid()",
                (database_name,),
            )
            cursor.execute(sql.SQL("DROP DATABASE {}").format(sql.Identifier(database_name)))
        admin_connection.close()


def _run_alembic(database_url: str, *arguments: str) -> None:
    env = os.environ.copy()
    env["DATABASE_URL"] = database_url
    env["DATABASE_URL_DIRECT"] = database_url
    result = subprocess.run(
        [sys.executable, "-m", "alembic", "-c", "api/alembic.ini", *arguments],
        cwd=BACKEND_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def _table_exists(connection: object, table_name: str) -> bool:
    with connection.cursor() as cursor:  # type: ignore[attr-defined]
        cursor.execute("SELECT to_regclass(%s)", (f"public.{table_name}",))
        return cursor.fetchone()[0] is not None


def _alembic_versions(connection: object) -> set[str]:
    with connection.cursor() as cursor:  # type: ignore[attr-defined]
        cursor.execute("SELECT version_num FROM alembic_version")
        return {row[0] for row in cursor.fetchall()}


def _row_security_enabled(connection: object, table_name: str) -> bool:
    with connection.cursor() as cursor:  # type: ignore[attr-defined]
        cursor.execute(
            "SELECT relrowsecurity FROM pg_class WHERE oid = %s::regclass",
            (f"public.{table_name}",),
        )
        return cursor.fetchone()[0] is True


def _table_policies(connection: object, table_name: str) -> set[str]:
    with connection.cursor() as cursor:  # type: ignore[attr-defined]
        cursor.execute(
            "SELECT policyname FROM pg_policies "
            "WHERE schemaname = 'public' AND tablename = %s",
            (table_name,),
        )
        return {row[0] for row in cursor.fetchall()}


def _client_grantees(connection: object, table_name: str) -> set[str]:
    with connection.cursor() as cursor:  # type: ignore[attr-defined]
        cursor.execute(
            "SELECT DISTINCT grantee FROM information_schema.role_table_grants "
            "WHERE table_schema = 'public' AND table_name = %s "
            "AND grantee IN ('anon', 'authenticated')",
            (table_name,),
        )
        return {row[0] for row in cursor.fetchall()}
