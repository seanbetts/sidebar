#!/usr/bin/env python3
"""Seed or delete test data for a user.

Usage:
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid>
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --dry-run
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --delete
    uv run backend/scripts/seed_test_user_data.py --user-id <uuid> --delete --dry-run
"""

from __future__ import annotations

import argparse
import logging
import sys
import uuid
from collections.abc import Iterable
from pathlib import Path
from types import SimpleNamespace

SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from db_env import setup_environment  # noqa: E402

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
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete seeded data instead of creating it.",
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


def main(argv: Iterable[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    try:
        user_id = validate_user_id(args.user_id)
    except ValueError as exc:
        logger.error(str(exc))
        return 2

    plan = build_seed_plan(args.seed_tag)

    if args.dry_run and not args.delete:
        summary = SimpleNamespace(
            notes=len(plan.notes),
            websites=len(plan.websites),
            conversations=len(plan.conversations),
            memories=len(plan.memories),
            task_groups=len(plan.task_groups),
            task_projects=len(plan.task_projects),
            tasks=len(plan.tasks),
            settings=1,
            scratchpad=1,
        )
        log_summary("Dry-run seed plan:", summary)
        return 0

    setup_environment(database_url=args.database_url, supabase=args.supabase)

    from api.db.session import SessionLocal, set_session_user_id  # noqa: E402
    from api.services.test_data_service import TestDataService  # noqa: E402

    with SessionLocal() as db:
        set_session_user_id(db, user_id)
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
