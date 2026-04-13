#!/usr/bin/env python3
"""Read-only PostgreSQL diagnostics for operational debugging."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine, text

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from scripts.ops_diagnostics_common import (  # noqa: E402
    EXIT_CONFIG,
    EXIT_FAILURE,
    EXIT_OK,
    build_result,
    config_error_result,
    load_local_env,
    print_json_result,
    print_text_result,
)


def build_db_summary(
    *,
    sessions_by_state: list[dict[str, Any]],
    idle_transactions: list[dict[str, Any]],
    blockers: list[dict[str, Any]],
    top_queries: list[dict[str, Any]] | None,
) -> dict[str, object]:
    """Build the top-level database summary payload."""
    warnings: list[str] = []
    status = "ok"
    if idle_transactions:
        status = "warn"
        warnings.append("idle transactions detected")
    if blockers:
        status = "warn"
        warnings.append("blocking queries detected")
    if top_queries is None:
        warnings.append("pg_stat_statements unavailable")

    return build_result(
        target="db",
        command="summary",
        status=status,
        data={
            "session_groups": sessions_by_state,
            "idle_in_transaction_count": len(idle_transactions),
            "blocker_count": len(blockers),
            "top_queries_available": top_queries is not None,
            "top_query_count": len(top_queries or []),
        },
        warnings=warnings,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run PostgreSQL diagnostics.")
    parser.add_argument(
        "command",
        nargs="?",
        default="summary",
        choices=[
            "summary",
            "activity",
            "idle-transactions",
            "locks",
            "blockers",
            "top-queries",
            "table-locks",
        ],
    )
    parser.add_argument("--table", help="Table name for table-locks output.")
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    load_local_env()
    args = parse_args(argv)
    database_url = os.environ.get("OPS_DB_URL", "").strip()
    if not database_url:
        result = config_error_result(
            target="db",
            command=args.command,
            missing_vars=["OPS_DB_URL"],
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_CONFIG

    try:
        engine = create_engine(database_url, pool_pre_ping=True)
        with engine.connect() as connection:
            result = _run_command(connection, args.command, table=args.table)
    except Exception as exc:
        result = build_result(
            target="db",
            command=args.command,
            status="error",
            errors=[str(exc)],
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_FAILURE
    finally:
        if "engine" in locals():
            engine.dispose()

    _print_result(result, as_json=args.as_json)
    return EXIT_OK


def _run_command(connection, command: str, *, table: str | None) -> dict[str, object]:
    if command == "summary":
        top_queries: list[dict[str, Any]] | None
        try:
            top_queries = _fetch_top_queries(connection)
        except Exception:
            top_queries = None
        return build_db_summary(
            sessions_by_state=_fetch_activity(connection),
            idle_transactions=_fetch_idle_transactions(connection),
            blockers=_fetch_blockers(connection),
            top_queries=top_queries,
        )
    if command == "activity":
        return build_result(
            target="db",
            command=command,
            status="ok",
            data={"rows": _fetch_activity(connection)},
        )
    if command == "idle-transactions":
        rows = _fetch_idle_transactions(connection)
        return build_result(
            target="db",
            command=command,
            status="warn" if rows else "ok",
            data={"rows": rows},
            warnings=["idle transactions detected"] if rows else [],
        )
    if command == "locks":
        return build_result(
            target="db",
            command=command,
            status="ok",
            data={"rows": _fetch_locks(connection)},
        )
    if command == "blockers":
        rows = _fetch_blockers(connection)
        return build_result(
            target="db",
            command=command,
            status="warn" if rows else "ok",
            data={"rows": rows},
            warnings=["blocking queries detected"] if rows else [],
        )
    if command == "top-queries":
        return build_result(
            target="db",
            command=command,
            status="ok",
            data={"rows": _fetch_top_queries(connection)},
        )
    if command == "table-locks":
        if not table:
            raise ValueError("--table is required for table-locks")
        return build_result(
            target="db",
            command=command,
            status="ok",
            data={"rows": _fetch_table_locks(connection, table)},
        )
    raise ValueError(f"Unsupported command: {command}")


def _fetch_activity(connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        text(
            """
            select
              coalesce(application_name, '') as application_name,
              coalesce(state, 'unknown') as state,
              count(*) as session_count
            from pg_stat_activity
            where datname = current_database()
              and pid <> pg_backend_pid()
            group by coalesce(application_name, ''), coalesce(state, 'unknown')
            order by session_count desc, application_name, state
            """
        )
    ).mappings()
    return [dict(row) for row in rows]


def _fetch_idle_transactions(connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        text(
            """
            select
              pid,
              usename,
              application_name,
              extract(epoch from (now() - xact_start))::bigint as xact_age_seconds,
              extract(epoch from (now() - query_start))::bigint as query_age_seconds,
              left(query, 300) as query
            from pg_stat_activity
            where datname = current_database()
              and state = 'idle in transaction'
            order by xact_start asc nulls last
            """
        )
    ).mappings()
    return [dict(row) for row in rows]


def _fetch_blockers(connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        text(
            """
            select
              blocked.pid as blocked_pid,
              blocker.pid as blocker_pid,
              blocked.application_name as blocked_application_name,
              blocker.application_name as blocker_application_name,
              left(blocked.query, 200) as blocked_query,
              left(blocker.query, 200) as blocker_query
            from pg_stat_activity blocked
            join pg_stat_activity blocker
              on blocker.pid = any(pg_blocking_pids(blocked.pid))
            order by blocked.query_start asc
            """
        )
    ).mappings()
    return [dict(row) for row in rows]


def _fetch_locks(connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        text(
            """
            select
              a.pid,
              a.application_name,
              l.locktype,
              l.mode,
              l.granted,
              left(a.query, 200) as query
            from pg_locks l
            join pg_stat_activity a on a.pid = l.pid
            where a.datname = current_database()
            order by l.granted desc, a.pid
            limit 100
            """
        )
    ).mappings()
    return [dict(row) for row in rows]


def _fetch_table_locks(connection, table: str) -> list[dict[str, Any]]:
    rows = connection.execute(
        text(
            """
            select
              a.pid,
              a.application_name,
              a.state,
              l.mode,
              l.granted,
              left(a.query, 200) as query
            from pg_locks l
            join pg_stat_activity a on a.pid = l.pid
            join pg_class c on c.oid = l.relation
            where c.relname = :table_name
            order by l.granted desc, a.pid
            """
        ),
        {"table_name": table},
    ).mappings()
    return [dict(row) for row in rows]


def _fetch_top_queries(connection) -> list[dict[str, Any]]:
    rows = connection.execute(
        text(
            """
            select
              calls,
              round(total_exec_time::numeric, 2) as total_exec_time,
              round(mean_exec_time::numeric, 2) as mean_exec_time,
              rows,
              left(query, 300) as query
            from pg_stat_statements
            order by total_exec_time desc
            limit 20
            """
        )
    ).mappings()
    return [dict(row) for row in rows]


def _print_result(result: dict[str, object], *, as_json: bool) -> None:
    if as_json:
        print_json_result(result)
        return
    print_text_result(result)


if __name__ == "__main__":
    raise SystemExit(main())
