#!/usr/bin/env python3
"""Seed or delete test data for a user.

Usage:
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid>
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --dry-run
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --delete
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --delete --dry-run
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --reset
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --now 2026-02-09T00:00:00Z
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
import uuid
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlparse

SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from .db_env import setup_environment  # noqa: E402

from api.services.test_data_plan import build_seed_plan  # noqa: E402

logger = logging.getLogger(__name__)


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Seed or delete test data for a user."
    )
    parser.add_argument("--user-id", required=True, help="User UUID to target.")
    parser.add_argument(
        "--seed-tag",
        default="seed:test-data",
        help="Marker used to tag seed data.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview actions without modifying the database.",
    )
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--delete",
        action="store_true",
        help="Delete seeded data instead of creating it.",
    )
    mode_group.add_argument(
        "--reset",
        action="store_true",
        help="Delete then reseed in one run.",
    )
    parser.add_argument(
        "--database-url",
        help="Override DATABASE_URL for this run.",
    )
    parser.add_argument(
        "--supabase",
        action="store_true",
        help="Force building DATABASE_URL from Supabase env vars.",
    )
    parser.add_argument(
        "--now",
        help="Optional deterministic timestamp (ISO-8601). Example: 2026-02-09T00:00:00Z",
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help="Allow execution when APP_ENV is production.",
    )
    return parser.parse_args(argv)


def validate_user_id(value: str) -> str:
    try:
        uuid.UUID(value)
    except ValueError as exc:
        raise ValueError("user-id must be a UUID.") from exc
    return value


def log_summary(prefix: str, summary: object) -> None:
    logger.info(
        "%s notes=%s websites=%s conversations=%s memories=%s tasks=%s projects=%s "
        "groups=%s settings=%s scratchpad=%s",
        prefix,
        getattr(summary, "notes"),
        getattr(summary, "websites"),
        getattr(summary, "conversations"),
        getattr(summary, "memories"),
        getattr(summary, "tasks"),
        getattr(summary, "task_projects"),
        getattr(summary, "task_groups"),
        getattr(summary, "settings"),
        getattr(summary, "scratchpad"),
    )


def parse_now(value: str | None) -> datetime | None:
    if value is None:
        return None
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise ValueError(
            "Invalid --now timestamp. Use ISO-8601, e.g. 2026-02-09T00:00:00Z."
        ) from exc
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed


def assert_safe_environment(*, allow_production: bool) -> None:
    app_env = os.getenv("APP_ENV", "").strip().lower()
    if app_env in {"prod", "production"} and not allow_production:
        db_url = os.getenv("DATABASE_URL", "")
        parsed = urlparse(db_url) if db_url else None
        host = parsed.hostname if parsed else None
        db_name = parsed.path.lstrip("/") if parsed and parsed.path else None
        raise RuntimeError(
            "Refusing to run seed script in production environment "
            f"(APP_ENV={app_env!r}, host={host!r}, database={db_name!r}). "
            "Re-run with --allow-production only if this is intentional."
        )


def plan_summary(plan: object) -> SimpleNamespace:
    return SimpleNamespace(
        notes=len(getattr(plan, "notes")),
        websites=len(getattr(plan, "websites")),
        conversations=len(getattr(plan, "conversations")),
        memories=len(getattr(plan, "memories")),
        task_groups=len(getattr(plan, "task_groups")),
        task_projects=len(getattr(plan, "task_projects")),
        tasks=len(getattr(plan, "tasks")),
        settings=1,
        scratchpad=1,
    )


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    try:
        user_id = validate_user_id(args.user_id)
    except ValueError as exc:
        logger.error(str(exc))
        return 2

    try:
        now = parse_now(args.now)
    except ValueError as exc:
        logger.error(str(exc))
        return 2

    plan = build_seed_plan(args.seed_tag, now=now)

    if args.dry_run and not args.delete and not args.reset:
        log_summary("Dry-run seed plan:", plan_summary(plan))
        return 0

    setup_environment(database_url=args.database_url, supabase=args.supabase)
    try:
        assert_safe_environment(allow_production=args.allow_production)
    except RuntimeError as exc:
        logger.error(str(exc))
        return 2

    from api.db.session import SessionLocal, set_session_user_id  # noqa: E402
    from api.services.test_data_service import TestDataService  # noqa: E402

    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        if args.reset:
            if args.dry_run:
                delete_summary = TestDataService.preview_delete(db, user_id, plan)
                log_summary("Dry-run reset delete:", delete_summary)
                log_summary("Dry-run reset seed:", plan_summary(plan))
                return 0
            deleted = TestDataService.delete_seed_data(db, user_id, plan)
            log_summary("Reset delete:", deleted)
            seeded = TestDataService.seed_user_data(db, user_id, plan)
            log_summary("Reset seed:", seeded)
            return 0
        if args.delete:
            if args.dry_run:
                summary = TestDataService.preview_delete(db, user_id, plan)
                log_summary("Dry-run delete plan:", summary)
                return 0
            summary = TestDataService.delete_seed_data(db, user_id, plan)
            log_summary("Deleted seed data:", summary)
            return 0

        summary = TestDataService.seed_user_data(db, user_id, plan)
        log_summary("Seeded test data:", summary)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
