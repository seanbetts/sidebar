#!/usr/bin/env python3
"""Read-only app queue diagnostics for worker and job health."""

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


STALE_JOB_MINUTES = 15
ACTIVE_JOB_STATUSES = {"queued", "processing"}


def build_app_summary(
    *,
    queue_counts: dict[str, dict[str, int]],
    stale_jobs: list[dict[str, Any]],
) -> dict[str, object]:
    """Build the top-level queue-health summary payload."""
    active_stale_jobs = [
        item
        for item in stale_jobs
        if str(item.get("status")) in ACTIVE_JOB_STATUSES
    ]
    stale_job_count = sum(int(item.get("stale_count", 0)) for item in active_stale_jobs)
    warnings: list[str] = []
    status = "ok"
    if stale_job_count > 0:
        status = "warn"
        warnings.append("stalled jobs detected")

    return build_result(
        target="app",
        command="summary",
        status=status,
        data={
            "queue_counts": queue_counts,
            "stale_jobs": active_stale_jobs,
            "stale_job_count": stale_job_count,
        },
        warnings=warnings,
    )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run app queue diagnostics.")
    parser.add_argument(
        "command",
        nargs="?",
        default="summary",
        choices=["summary", "queues", "stale-jobs"],
    )
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    load_local_env()
    args = parse_args(argv)
    database_url = os.environ.get("OPS_DB_URL", "").strip()
    if not database_url:
        result = config_error_result(
            target="app",
            command=args.command,
            missing_vars=["OPS_DB_URL"],
        )
        _print_result(result, as_json=args.as_json)
        return EXIT_CONFIG

    try:
        engine = create_engine(database_url, pool_pre_ping=True)
        with engine.connect() as connection:
            queue_counts = _fetch_queue_counts(connection)
            stale_jobs = _fetch_stale_jobs(connection)
            if args.command == "summary":
                result = build_app_summary(
                    queue_counts=queue_counts,
                    stale_jobs=stale_jobs,
                )
            elif args.command == "queues":
                result = build_result(
                    target="app",
                    command=args.command,
                    status="ok",
                    data={"queue_counts": queue_counts},
                )
            else:
                result = build_result(
                    target="app",
                    command=args.command,
                    status="warn" if stale_jobs else "ok",
                    data={"stale_jobs": stale_jobs},
                    warnings=["stalled jobs detected"] if stale_jobs else [],
                )
    except Exception as exc:
        result = build_result(
            target="app",
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


def _fetch_queue_counts(connection) -> dict[str, dict[str, int]]:
    return {
        "website_processing_jobs": _fetch_status_counts(
            connection,
            "website_processing_jobs",
        ),
        "file_processing_jobs": _fetch_status_counts(connection, "file_processing_jobs"),
    }


def _fetch_status_counts(connection, table_name: str) -> dict[str, int]:
    rows = connection.execute(
        text(
            f"""
            select status, count(*) as count
            from {table_name}
            group by status
            order by status
            """
        )
    ).mappings()
    return {str(row["status"]): int(row["count"]) for row in rows}


def _fetch_stale_jobs(connection) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for table_name in ("website_processing_jobs", "file_processing_jobs"):
        results = connection.execute(
            text(
                f"""
                select
                  :table_name as queue,
                  status,
                  count(*) as stale_count
                from {table_name}
                where status in ('queued', 'processing')
                  and (
                    updated_at < now() - make_interval(mins => :stale_minutes)
                    or (
                      lease_expires_at is not null
                      and lease_expires_at < now()
                    )
                  )
                group by status
                order by status
                """
            ),
            {"table_name": table_name, "stale_minutes": STALE_JOB_MINUTES},
        ).mappings()
        rows.extend(dict(row) for row in results)
    return rows


def _print_result(result: dict[str, object], *, as_json: bool) -> None:
    if as_json:
        print_json_result(result)
        return
    print_text_result(result)


if __name__ == "__main__":
    raise SystemExit(main())
