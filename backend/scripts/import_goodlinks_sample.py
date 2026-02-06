#!/usr/bin/env python3
"""Import a random sample of GoodLinks URLs using the full ingestion pipeline.

Usage:
    cd backend
    uv run python scripts/import_goodlinks_sample.py \
        --user-id USER_ID \
        --export-path goodlinks-testing/GoodLinks-Export-2025.json \
        --limit 10 \
        --supabase
"""

from __future__ import annotations

import argparse
import json
import logging
import random
import sys
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from db_env import setup_environment  # noqa: E402

logger = logging.getLogger(__name__)


class _SkipRuthlessRemovalFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        return "ruthless removal did not work." not in record.getMessage()


def parse_datetime(value: str | int | float | None) -> datetime | None:
    if not value:
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(value, tz=UTC)
        except (OSError, ValueError):
            return None
    cleaned = str(value).strip()
    try:
        parsed = datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=UTC)
        return parsed
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


def ingest_url_via_pipeline(
    user_id: str,
    *,
    url: str,
    added_at: datetime | None,
    archived: bool,
) -> None:
    """Ingest a URL via the app's quick-save pipeline and apply GoodLinks metadata."""
    from api.db.session import SessionLocal, set_session_user_id
    from api.routers.websites_helpers import run_quick_save
    from api.services.website_processing_service import WebsiteProcessingService
    from api.services.websites_service import WebsitesService

    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        job = WebsiteProcessingService.create_job(db, user_id, url)

    run_quick_save(job.id, user_id, url, None)

    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        completed_job = WebsiteProcessingService.get_job(db, user_id, job.id)
        if (
            completed_job is None
            or completed_job.status != "completed"
            or completed_job.website_id is None
        ):
            error_message = (
                completed_job.error_message if completed_job else "job not found"
            )
            raise RuntimeError(
                f"Ingestion pipeline failed for {url}: {error_message or 'unknown error'}"
            )

        if added_at is not None:
            WebsitesService.update_website(
                db,
                user_id,
                completed_job.website_id,
                saved_at=added_at,
            )
        if archived:
            WebsitesService.update_archived(
                db,
                user_id,
                completed_job.website_id,
                archived=True,
            )


def import_sample(
    user_id: str,
    *,
    export_path: Path,
    limit: int,
    seed: int | None,
    dry_run: bool,
    log_every: int,
    import_all: bool,
    archived: bool,
) -> None:
    payload = json.loads(export_path.read_text(encoding="utf-8"))
    entries = iter_export_entries(payload)
    urls = []
    for entry in entries:
        url = entry.get("url")
        if isinstance(url, str) and url.startswith(("http://", "https://")):
            urls.append(entry)

    if not urls:
        raise ValueError("No URLs found in GoodLinks export.")

    if import_all:
        sample = urls
        total = len(sample)
    else:
        if limit <= 0:
            raise ValueError("--limit must be greater than 0 unless --all is used.")
        if limit > len(urls):
            limit = len(urls)
        rng = random.Random(seed)
        sample = rng.sample(urls, k=limit)
        total = len(sample)
    created = 0
    failed = 0
    for idx, entry in enumerate(sample, start=1):
        url = entry.get("url")
        added_at = parse_datetime(entry.get("addedAt"))
        try:
            if not isinstance(url, str):
                raise ValueError("Export entry missing URL.")
            logger.info("Ingesting %s", url)
            if dry_run:
                logger.info(
                    "Dry run: would ingest url=%s saved_at=%s archived=%s",
                    url,
                    added_at.isoformat() if added_at else None,
                    archived,
                )
            else:
                ingest_url_via_pipeline(
                    user_id,
                    url=url,
                    added_at=added_at,
                    archived=archived,
                )
            created += 1
        except Exception as exc:
            failed += 1
            logger.warning("Failed to import %s: %s", url, str(exc))
        if log_every > 0 and (idx % log_every == 0 or idx == total):
            logger.info(
                "Progress: %s/%s imported=%s failed=%s",
                idx,
                total,
                created,
                failed,
            )

    logger.info(
        "Import complete. Imported=%s Failed=%s Total=%s", created, failed, total
    )


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import random GoodLinks URLs.")
    parser.add_argument("--user-id", required=True, help="User ID to import into.")
    parser.add_argument(
        "--export-path",
        required=True,
        help="Path to GoodLinks export JSON.",
    )
    parser.add_argument(
        "--limit", type=int, default=10, help="Number of URLs to import."
    )
    parser.add_argument(
        "--seed", type=int, default=None, help="Random seed for repeatable samples."
    )
    parser.add_argument("--dry-run", action="store_true", help="Log without writing.")
    parser.add_argument(
        "--all",
        action="store_true",
        help="Import every URL in the export (ignores --limit/--seed).",
    )
    parser.add_argument(
        "--log-every",
        type=int,
        default=25,
        help="Log progress every N URLs (0 disables progress logs).",
    )
    parser.add_argument(
        "--archived",
        default=True,
        action=argparse.BooleanOptionalAction,
        help="Mark imported websites as archived (default: enabled).",
    )
    parser.add_argument(
        "--database-url",
        help="Optional database URL override (uses env by default).",
    )
    parser.add_argument(
        "--supabase",
        action="store_true",
        help="Prompt for Supabase pooler credentials if not set.",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    logging.getLogger().addFilter(_SkipRuthlessRemovalFilter())
    logging.getLogger("api.services.web_save_parser").setLevel(logging.WARNING)
    setup_environment(database_url=args.database_url, supabase=args.supabase)
    if str(BACKEND_ROOT) not in sys.path:
        sys.path.insert(0, str(BACKEND_ROOT))
    import_sample(
        args.user_id,
        export_path=Path(args.export_path),
        limit=args.limit,
        seed=args.seed,
        dry_run=args.dry_run,
        log_every=args.log_every,
        import_all=args.all,
        archived=args.archived,
    )


if __name__ == "__main__":
    main()
