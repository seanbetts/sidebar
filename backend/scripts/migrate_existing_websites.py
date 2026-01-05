#!/usr/bin/env python3
"""
Migrate existing websites to the new parsing pipeline.

Usage:
    uv run backend/scripts/migrate_existing_websites.py --user-id USER_ID
"""
from __future__ import annotations

import argparse
import logging
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable, Optional

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from api.db.session import SessionLocal, set_session_user_id
from api.models.website import Website
from api.services.web_save_parser import ParsedPage, parse_url_local
from api.services.websites_service import WebsitesService

logger = logging.getLogger(__name__)


def iter_websites(
    db,
    user_id: str,
    *,
    include_deleted: bool,
    limit: Optional[int],
) -> list[Website]:
    query = db.query(Website).filter(Website.user_id == user_id)
    if not include_deleted:
        query = query.filter(Website.deleted_at.is_(None))
    query = query.order_by(Website.created_at.asc())
    if limit:
        query = query.limit(limit)
    return query.all()


def migrate_websites(
    user_id: str,
    *,
    include_deleted: bool,
    limit: Optional[int],
    dry_run: bool,
    stop_on_error: bool,
) -> None:
    db = SessionLocal()
    set_session_user_id(db, user_id)
    websites = iter_websites(db, user_id, include_deleted=include_deleted, limit=limit)
    total = len(websites)
    logger.info("Found %s website(s) to migrate.", total)
    migrated = 0
    failed = 0
    error_types: Counter[str] = Counter()

    try:
        for website in websites:
            url = website.url_full or website.url
            try:
                parsed: ParsedPage = parse_url_local(url)
                if dry_run:
                    logger.info("DRY RUN: would migrate %s (%s)", website.id, url)
                else:
                    WebsitesService.update_website(
                        db,
                        user_id,
                        website.id,
                        title=parsed.title,
                        content=parsed.content,
                        source=parsed.source,
                        saved_at=website.saved_at,
                        published_at=parsed.published_at,
                    )
                    logger.info("Migrated %s (%s)", website.id, url)
                migrated += 1
            except Exception as exc:
                failed += 1
                error_types[type(exc).__name__] += 1
                logger.warning(
                    "Failed to migrate %s (%s): %s",
                    website.id,
                    url,
                    str(exc),
                )
                if stop_on_error:
                    break
    finally:
        db.close()

    logger.info("Migration complete. Migrated=%s Failed=%s Total=%s", migrated, failed, total)
    if error_types:
        summary = ", ".join(f"{name}={count}" for name, count in error_types.most_common(5))
        logger.info("Top error types: %s", summary)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Migrate existing websites to new parser.")
    parser.add_argument("--user-id", required=True, help="User ID to migrate.")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of websites.")
    parser.add_argument("--include-deleted", action="store_true", help="Include soft-deleted records.")
    parser.add_argument("--dry-run", action="store_true", help="Log actions without updating.")
    parser.add_argument(
        "--stop-on-error",
        action="store_true",
        help="Stop migration on first error.",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Iterable[str]] = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    migrate_websites(
        args.user_id,
        include_deleted=args.include_deleted,
        limit=args.limit,
        dry_run=args.dry_run,
        stop_on_error=args.stop_on_error,
    )


if __name__ == "__main__":
    main()
