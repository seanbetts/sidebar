#!/usr/bin/env python3
"""Audit Supabase shared-pooler usage from pg_stat_statements."""

from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Protocol
from urllib.parse import quote_plus

from sqlalchemy import create_engine, text

# Ensure backend package root is importable when running as a script.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from scripts.db_env import setup_environment  # noqa: E402


@dataclass(frozen=True)
class QueryStat:
    """Normalized statement statistics for report output."""

    queryid: int
    calls: int
    rows: int
    total_ms: float
    mean_ms: float
    query: str


@dataclass(frozen=True)
class EgressEstimate:
    """Approximate egress estimate for one known query shape."""

    label: str
    rows: int
    avg_row_bytes: float
    estimated_gb: float


@dataclass(frozen=True)
class AuditReport:
    """Human-readable audit payload."""

    stats_reset: datetime
    statement_count: int
    total_calls: int
    total_rows: int
    top_by_rows: list[QueryStat]
    top_by_time: list[QueryStat]
    estimates: list[EgressEstimate]


class AuditBackend(Protocol):
    """Minimal backend interface for running the audit."""

    def reset_stats(self) -> datetime:
        """Reset pg_stat_statements and return the reset timestamp."""

    def collect_report(self) -> AuditReport:
        """Collect current statement statistics and estimates."""


@dataclass(frozen=True)
class EstimateDefinition:
    """Definition for one project-specific estimate."""

    label: str
    avg_row_sql: str


ESTIMATE_DEFINITIONS: dict[str, EstimateDefinition] = {
    "conversations list": EstimateDefinition(
        label="conversations list",
        avg_row_sql="""
            select avg(octet_length(row_to_json(t)::text))
            from (
                select
                    id,
                    title,
                    title_generated,
                    created_at,
                    updated_at,
                    first_message,
                    message_count
                from conversations
                where is_archived is false
            ) t
        """,
    ),
    "notes metadata list": EstimateDefinition(
        label="notes metadata list",
        avg_row_sql="""
            select avg(octet_length(row_to_json(t)::text))
            from (
                select
                    id,
                    title,
                    metadata,
                    is_archived,
                    created_at,
                    updated_at
                from notes
                where deleted_at is null and is_archived is false
            ) t
        """,
    ),
    "notes full list": EstimateDefinition(
        label="notes full list",
        avg_row_sql="""
            select avg(octet_length(row_to_json(t)::text))
            from (
                select
                    id,
                    title,
                    document,
                    document_version,
                    plain_text,
                    folder_path,
                    pinned,
                    pinned_order,
                    is_folder_marker,
                    is_archived,
                    created_at,
                    updated_at
                from notes
                where deleted_at is null and is_archived is false
            ) t
        """,
    ),
    "notes plain_text list": EstimateDefinition(
        label="notes plain_text list",
        avg_row_sql="""
            select avg(octet_length(row_to_json(t)::text))
            from (
                select
                    id,
                    title,
                    plain_text,
                    folder_path,
                    pinned,
                    pinned_order,
                    is_folder_marker,
                    is_archived,
                    created_at,
                    updated_at
                from notes
                where deleted_at is null and is_archived is false
            ) t
        """,
    ),
    "websites list": EstimateDefinition(
        label="websites list",
        avg_row_sql="""
            select avg(octet_length(row_to_json(t)::text))
            from (
                select
                    id,
                    url,
                    domain,
                    title,
                    saved_at,
                    published_at,
                    reading_time,
                    metadata,
                    is_archived,
                    updated_at,
                    created_at,
                    last_opened_at,
                    deleted_at
                from websites
                where deleted_at is null
            ) t
        """,
    ),
    "website content by id": EstimateDefinition(
        label="website content by id",
        avg_row_sql="select avg(octet_length(coalesce(content, ''))) from websites",
    ),
}


class PostgresAuditBackend:
    """Postgres-backed implementation of the audit workflow."""

    def __init__(self, engine) -> None:
        self._engine = engine

    def reset_stats(self) -> datetime:
        """Reset pg_stat_statements and return the reset time."""
        with self._engine.begin() as conn:
            return conn.execute(text("select pg_stat_statements_reset()")).scalar_one()

    def collect_report(self) -> AuditReport:
        """Collect statement stats and project-specific estimates."""
        with self._engine.connect() as conn:
            stats_reset = conn.execute(
                text("select stats_reset from pg_stat_statements_info")
            ).scalar_one()
            all_stats = [
                stat for stat in _fetch_query_stats(conn, order_by="queryid asc")
                if not _is_internal_query(stat.query)
            ]
            top_by_rows = sorted(
                all_stats,
                key=lambda stat: (stat.rows, stat.calls, stat.total_ms),
                reverse=True,
            )[:10]
            top_by_time = sorted(
                all_stats,
                key=lambda stat: (stat.total_ms, stat.calls, stat.rows),
                reverse=True,
            )[:10]
            estimates = _collect_estimates(conn, all_stats)
        return AuditReport(
            stats_reset=stats_reset,
            statement_count=len(all_stats),
            total_calls=sum(stat.calls for stat in all_stats),
            total_rows=sum(stat.rows for stat in all_stats),
            top_by_rows=top_by_rows,
            top_by_time=top_by_time,
            estimates=estimates,
        )


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description=(
            "Audit Supabase shared-pooler usage from pg_stat_statements. "
            "Read-only by default; use --reset to start a clean measurement window."
        )
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Reset pg_stat_statements before collecting the report.",
    )
    return parser.parse_args(argv)


def execute_audit(backend: AuditBackend, *, reset: bool) -> AuditReport:
    """Optionally reset stats, then collect a report."""
    if reset:
        backend.reset_stats()
    return backend.collect_report()


def render_report(report: AuditReport) -> str:
    """Render a human-readable audit report."""
    lines = [
        "Supabase Shared Pooler Egress Audit",
        f"Stats reset: {_format_timestamp(report.stats_reset)}",
        f"Statements tracked: {report.statement_count}",
        f"Total calls: {report.total_calls}",
        f"Total rows returned: {report.total_rows}",
        "",
        "Top queries by rows",
    ]
    lines.extend(_render_query_stats(report.top_by_rows))
    lines.append("")
    lines.append("Top queries by total execution time")
    lines.extend(_render_query_stats(report.top_by_time))
    lines.append("")
    lines.append("Estimated large-result contributors")
    if report.estimates:
        for estimate in report.estimates:
            lines.append(
                f"- {estimate.label}: rows={estimate.rows}, "
                f"avg_row_bytes={estimate.avg_row_bytes:.1f}, "
                f"estimated_gb={estimate.estimated_gb:.3f}"
            )
    else:
        lines.append("- No known high-egress query shapes matched the current stats window.")
    lines.append("")
    lines.append("Note: estimates are approximate and based on current row payload size.")
    return "\n".join(lines)


def _render_query_stats(stats: list[QueryStat]) -> list[str]:
    """Render one query-stat section."""
    if not stats:
        return ["- No statements tracked in this window."]
    lines: list[str] = []
    for stat in stats:
        lines.append(
            f"- calls={stat.calls} rows={stat.rows} total_ms={stat.total_ms:.2f} "
            f"mean_ms={stat.mean_ms:.2f} query={stat.query}"
        )
    return lines


def _fetch_query_stats(conn, *, order_by: str, limit: int | None = None) -> list[QueryStat]:
    """Fetch normalized statement stats ordered by the requested key."""
    sql = f"""
        select
            queryid,
            calls,
            rows,
            total_exec_time,
            total_exec_time / nullif(calls, 0) as mean_exec_time,
            regexp_replace(query, '\\s+', ' ', 'g') as query
        from pg_stat_statements
        where dbid = (select oid from pg_database where datname = current_database())
        order by {order_by}
    """
    if limit is not None:
        sql += f" limit {int(limit)}"
    rows = conn.execute(text(sql)).mappings().all()
    return [
        QueryStat(
            queryid=int(row["queryid"]),
            calls=int(row["calls"]),
            rows=int(row["rows"]),
            total_ms=float(row["total_exec_time"] or 0.0),
            mean_ms=float(row["mean_exec_time"] or 0.0),
            query=str(row["query"]).strip(),
        )
        for row in rows
    ]


def _collect_estimates(conn, stats: list[QueryStat]) -> list[EgressEstimate]:
    """Estimate egress for known query shapes found in the current window."""
    grouped_rows: dict[str, int] = defaultdict(int)
    for stat in stats:
        label = _match_estimate_label(stat.query)
        if label is not None and stat.rows > 0:
            grouped_rows[label] += stat.rows

    estimates: list[EgressEstimate] = []
    for label, rows in grouped_rows.items():
        definition = ESTIMATE_DEFINITIONS[label]
        avg_row_bytes = float(
            conn.execute(text(definition.avg_row_sql)).scalar_one_or_none() or 0.0
        )
        estimated_gb = avg_row_bytes * rows / 1024 / 1024 / 1024
        estimates.append(
            EgressEstimate(
                label=definition.label,
                rows=rows,
                avg_row_bytes=avg_row_bytes,
                estimated_gb=estimated_gb,
            )
        )
    estimates.sort(key=lambda item: item.estimated_gb, reverse=True)
    return estimates


def _match_estimate_label(query: str) -> str | None:
    """Map a statement query to a known project-specific estimate bucket."""
    normalized = " ".join(query.split())
    if (
        "FROM notes" in normalized
        and "notes.metadata AS notes_metadata" in normalized
        and "notes.document AS notes_document" not in normalized
        and "notes.plain_text AS notes_plain_text" not in normalized
    ):
        return "notes metadata list"
    if (
        "FROM notes" in normalized
        and "notes.document AS notes_document" in normalized
        and "notes.plain_text AS notes_plain_text" in normalized
    ):
        return "notes full list"
    if "FROM notes" in normalized and "notes.plain_text AS notes_plain_text" in normalized:
        return "notes plain_text list"
    if "FROM conversations" in normalized and "conversations.first_message" in normalized:
        return "conversations list"
    if (
        normalized.startswith("SELECT websites.content AS websites_content")
        and "FROM websites" in normalized
    ):
        return "website content by id"
    if (
        "FROM websites" in normalized
        and "websites.metadata AS websites_metadata" in normalized
        and "ORDER BY websites.saved_at DESC" in normalized
    ):
        return "websites list"
    return None


def _is_internal_query(query: str) -> bool:
    """Return whether a statement originates from this audit script itself."""
    normalized = " ".join(query.split()).lower()
    internal_patterns = (
        "from pg_stat_statements",
        "pg_stat_statements_info",
        "pg_stat_statements_reset()",
        "select pg_catalog.version()",
        "select current_schema()",
    )
    return any(pattern in normalized for pattern in internal_patterns)


def _format_timestamp(value: datetime) -> str:
    """Render a UTC timestamp in a stable format."""
    return value.astimezone(UTC).strftime("%Y-%m-%d %H:%M:%S UTC")


def _strip_quotes(value: str | None) -> str:
    """Strip wrapping single or double quotes from env values."""
    return (value or "").strip().strip('"').strip("'")


def _build_admin_database_url() -> str:
    """Build a stable Supabase admin connection URL for audit queries."""
    setup_environment(set_anthropic_placeholder=False)
    project_id = _strip_quotes(os.environ.get("SUPABASE_PROJECT_ID"))
    host = _strip_quotes(os.environ.get("SUPABASE_POOLER_HOST"))
    if not project_id or not host:
        raise RuntimeError("Missing SUPABASE_PROJECT_ID or SUPABASE_POOLER_HOST.")

    password = _strip_quotes(
        os.environ.get("SUPABASE_POSTGRES_PSWD") or os.environ.get("SUPABASE_APP_PSWD")
    )
    if not password:
        raise RuntimeError("Missing Supabase DB password for audit script.")

    db_name = _strip_quotes(os.environ.get("SUPABASE_DB_NAME")) or "postgres"
    sslmode = _strip_quotes(os.environ.get("SUPABASE_SSLMODE")) or "require"
    port = _strip_quotes(os.environ.get("SUPABASE_POOLER_PORT")) or "6543"
    if (_strip_quotes(os.environ.get("SUPABASE_POOLER_MODE")) or "transaction").lower() == "transaction":
        port = "6543"

    user = f"postgres.{project_id}"
    return (
        f"postgresql://{user}:{quote_plus(password)}@{host}:{port}/{db_name}"
        f"?sslmode={sslmode}"
    )


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    args = parse_args(argv)
    engine = create_engine(_build_admin_database_url(), pool_pre_ping=True)
    try:
        backend = PostgresAuditBackend(engine)
        report = execute_audit(backend, reset=bool(args.reset))
        print(render_report(report))
    finally:
        engine.dispose()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
