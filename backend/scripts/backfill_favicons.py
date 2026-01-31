#!/usr/bin/env python3
"""Backfill website favicons for existing records."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
import sys

sys.path.insert(0, str(BACKEND_ROOT))

from api.db.session import SessionLocal
from api.services.favicon_service import FaviconService
from api.services.web_save_parser import resolve_favicon_url
from api.services.websites_service import WebsitesService

logger = logging.getLogger(__name__)


def backfill_favicons(
    *,
    limit: int | None,
    offset: int | None,
    dry_run: bool,
    only_missing: bool,
) -> None:
    db = SessionLocal()
    processed = 0
    updated = 0
    try:
        websites = WebsitesService.list_websites_for_favicon_backfill(
            db,
            limit=limit,
            offset=offset,
            only_missing=only_missing,
        )
        for website in websites:
            processed += 1
            metadata = website.metadata_ or {}
            existing_key = metadata.get("favicon_r2_key")
            shared_key = FaviconService.build_storage_key(website.domain)
            if only_missing and existing_key == shared_key:
                continue

            shared_existing = FaviconService.existing_storage_key(website.domain)
            if shared_existing:
                if dry_run:
                    updated += 1
                else:
                    WebsitesService.update_metadata(
                        db,
                        website.user_id,
                        website.id,
                        metadata_updates={"favicon_r2_key": shared_existing},
                    )
                    updated += 1
                continue

            favicon_url = metadata.get("favicon_url")
            if not favicon_url:
                favicon_url = resolve_favicon_url(
                    None, website.source or website.url
                )
                if favicon_url and not dry_run:
                    payload = FaviconService.metadata_payload(favicon_url=favicon_url)
                    WebsitesService.update_metadata(
                        db,
                        website.user_id,
                        website.id,
                        metadata_updates=payload,
                    )

            if not favicon_url:
                continue

            favicon_key = FaviconService.fetch_and_store_favicon(
                website.domain,
                favicon_url,
            )
            if not favicon_key:
                continue
            if dry_run:
                updated += 1
                continue
            WebsitesService.update_metadata(
                db,
                website.user_id,
                website.id,
                metadata_updates={"favicon_r2_key": favicon_key},
            )
            updated += 1

        logger.info("favicon backfill processed=%s updated=%s", processed, updated)
    finally:
        db.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Backfill website favicons")
    parser.add_argument("--limit", type=int, help="Limit number of websites")
    parser.add_argument("--offset", type=int, help="Offset for pagination")
    parser.add_argument(
        "--dry-run", action="store_true", help="Process without writing updates"
    )
    parser.add_argument(
        "--only-missing",
        action="store_true",
        help="Only process records missing shared favicon key",
    )
    args = parser.parse_args()
    backfill_favicons(
        limit=args.limit,
        offset=args.offset,
        dry_run=args.dry_run,
        only_missing=args.only_missing,
    )


if __name__ == "__main__":
    main()
