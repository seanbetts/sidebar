#!/usr/bin/env python3
"""Backfill `websites.reading_time` values from stored website content."""

from __future__ import annotations

import argparse
import logging
import sys
from collections.abc import Iterable
from pathlib import Path

from sqlalchemy.orm import load_only
from sqlalchemy.orm.attributes import flag_modified

BACKEND_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from db_env import setup_environment  # noqa: E402

logger = logging.getLogger(__name__)


def backfill_reading_time(
    *,
    user_id: str | None,
    limit: int | None,
    batch_size: int,
    include_deleted: bool,
    only_missing: bool,
    dry_run: bool,
) -> None:
    """Backfill reading_time for website records."""
    from api.db.session import SessionLocal
    from api.models.website import Website
    from api.services.website_reading_time import derive_reading_time

    db = SessionLocal()
    processed = 0
    updated = 0
    committed = 0
    try:
        query = db.query(Website).options(
            load_only(
                Website.id,
                Website.user_id,
                Website.content,
                Website.reading_time,
                Website.metadata_,
                Website.deleted_at,
            )
        )
        if user_id:
            query = query.filter(Website.user_id == user_id)
        if not include_deleted:
            query = query.filter(Website.deleted_at.is_(None))
        if only_missing:
            query = query.filter(Website.reading_time.is_(None))
        query = query.order_by(Website.created_at.asc(), Website.id.asc())
        if limit:
            query = query.limit(limit)

        pending = 0
        for website in query.yield_per(batch_size):
            processed += 1
            computed = derive_reading_time(website.content)
            metadata = dict(website.metadata_ or {})
            previous = website.reading_time
            changed = previous != computed or metadata.get("reading_time") != computed
            if not changed:
                continue

            if dry_run:
                updated += 1
                continue

            website.reading_time = computed
            if computed:
                metadata["reading_time"] = computed
            else:
                metadata.pop("reading_time", None)
            website.metadata_ = metadata
            flag_modified(website, "metadata_")
            updated += 1
            pending += 1

            if pending >= batch_size:
                db.commit()
                committed += pending
                pending = 0

        if not dry_run and pending > 0:
            db.commit()
            committed += pending

        logger.info(
            "reading_time backfill processed=%s updated=%s committed=%s dry_run=%s",
            processed,
            updated,
            committed,
            dry_run,
        )
    finally:
        db.close()


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    """Parse CLI arguments for reading-time backfill."""
    parser = argparse.ArgumentParser(
        description="Backfill websites.reading_time from existing website content."
    )
    parser.add_argument(
        "--user-id",
        default=None,
        help="Optional user ID scope. Omit to process all users.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional max number of records to process.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=200,
        help="Rows per streaming/commit batch.",
    )
    parser.add_argument(
        "--include-deleted",
        action="store_true",
        help="Include soft-deleted website rows.",
    )
    parser.add_argument(
        "--only-missing",
        default=True,
        action=argparse.BooleanOptionalAction,
        help="Only process rows with NULL reading_time (default: enabled).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute/log update count without writing to DB.",
    )
    parser.add_argument(
        "--database-url",
        help="Optional DATABASE_URL override for this run.",
    )
    parser.add_argument(
        "--supabase",
        action="store_true",
        help="Prompt for Supabase pooler credentials if needed.",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> None:
    """Run the reading-time backfill script."""
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    setup_environment(database_url=args.database_url, supabase=args.supabase)
    if str(BACKEND_ROOT) not in sys.path:
        sys.path.insert(0, str(BACKEND_ROOT))

    backfill_reading_time(
        user_id=args.user_id,
        limit=args.limit,
        batch_size=max(1, args.batch_size),
        include_deleted=args.include_deleted,
        only_missing=args.only_missing,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
