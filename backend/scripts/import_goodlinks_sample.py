#!/usr/bin/env python3
"""
Import a random sample of GoodLinks URLs into Website records.

Usage:
    uv run backend/scripts/import_goodlinks_sample.py \
        --user-id USER_ID \
        --export-path goodlinks-testing/GoodLinks-Export-2025.json \
        --limit 10
"""
from __future__ import annotations

import argparse
import json
import logging
import random
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Optional

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from api.db.session import SessionLocal, set_session_user_id
from api.services.web_save_parser import ParsedPage, parse_url_local
from api.services.websites_service import WebsitesService

logger = logging.getLogger(__name__)


def parse_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(value, tz=timezone.utc)
        except (OSError, ValueError):
            return None
    cleaned = str(value).strip()
    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None


def iter_export_entries(payload: object) -> list[dict]:
    if isinstance(payload, list):
        return [entry for entry in payload if isinstance(entry, dict)]
    if isinstance(payload, dict):
        for value in payload.values():
            if isinstance(value, list):
                return [entry for entry in value if isinstance(entry, dict)]
    return []


def import_sample(
    user_id: str,
    *,
    export_path: Path,
    limit: int,
    seed: Optional[int],
    dry_run: bool,
) -> None:
    payload = json.loads(export_path.read_text())
    entries = iter_export_entries(payload)
    urls = []
    for entry in entries:
        url = entry.get("url")
        if isinstance(url, str) and url.startswith(("http://", "https://")):
            urls.append(entry)

    if not urls:
        raise ValueError("No URLs found in GoodLinks export.")

    if limit > len(urls):
        limit = len(urls)
    rng = random.Random(seed)
    sample = rng.sample(urls, k=limit)

    db = SessionLocal()
    set_session_user_id(db, user_id)
    created = 0
    failed = 0
    try:
        for entry in sample:
            url = entry.get("url")
            added_at = parse_datetime(entry.get("addedAt"))
            try:
                parsed: ParsedPage = parse_url_local(url)
                if dry_run:
                    logger.info("DRY RUN: would import %s", url)
                else:
                    WebsitesService.upsert_website(
                        db,
                        user_id,
                        url=url,
                        url_full=url,
                        title=parsed.title,
                        content=parsed.content,
                        source=parsed.source,
                        saved_at=added_at or datetime.now(timezone.utc),
                        published_at=parsed.published_at,
                    )
                    logger.info("Imported %s", url)
                created += 1
            except Exception as exc:
                failed += 1
                logger.warning("Failed to import %s: %s", url, str(exc))
    finally:
        db.close()

    logger.info("Import complete. Imported=%s Failed=%s Total=%s", created, failed, limit)


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import random GoodLinks URLs.")
    parser.add_argument("--user-id", required=True, help="User ID to import into.")
    parser.add_argument(
        "--export-path",
        required=True,
        help="Path to GoodLinks export JSON.",
    )
    parser.add_argument("--limit", type=int, default=10, help="Number of URLs to import.")
    parser.add_argument("--seed", type=int, default=None, help="Random seed for repeatable samples.")
    parser.add_argument("--dry-run", action="store_true", help="Log without writing.")
    return parser.parse_args(argv)


def main(argv: Optional[Iterable[str]] = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    import_sample(
        args.user_id,
        export_path=Path(args.export_path),
        limit=args.limit,
        seed=args.seed,
        dry_run=args.dry_run,
    )


if __name__ == "__main__":
    main()
