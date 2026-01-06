#!/usr/bin/env python3
"""
Migrate existing websites to the new parsing pipeline.

Usage:
    uv run backend/scripts/migrate_existing_websites.py --user-id USER_ID
    uv run backend/scripts/migrate_existing_websites.py --user-id USER_ID --pinned true --limit 6
"""
from __future__ import annotations

import argparse
import getpass
import logging
import os
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable, Optional, TYPE_CHECKING
from urllib.parse import urlparse, urlunparse, urlencode

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def load_doppler_env() -> None:
    token = os.environ.get("DOPPLER_TOKEN")
    if not token:
        return
    if not shutil.which("doppler"):
        return
    project = os.environ.get("DOPPLER_PROJECT")
    config = os.environ.get("DOPPLER_CONFIG")
    if not project or not config:
        return
    result = subprocess.run(
        [
            "doppler",
            "secrets",
            "download",
            "--no-file",
            "--format",
            "env",
            "--project",
            project,
            "--config",
            config,
        ],
        check=False,
        capture_output=True,
        text=True,
        env={**os.environ, "DOPPLER_TOKEN": token},
    )
    if result.returncode != 0:
        logging.warning("Doppler secrets download failed: %s", result.stderr.strip())
        return
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ[key.strip()] = value.strip()


def build_pooler_database_url() -> str | None:
    pooler_url = os.environ.get("SUPABASE_POOLER_URL")
    pooler_host = os.environ.get("SUPABASE_POOLER_HOST")
    password = os.environ.get("SUPABASE_APP_PSWD") or os.environ.get("SUPABASE_POSTGRES_PSWD")
    username = os.environ.get("SUPABASE_POOLER_USER")
    db_name = os.environ.get("SUPABASE_DB_NAME", "postgres")
    sslmode = os.environ.get("SUPABASE_SSLMODE", "require")
    pooler_mode = os.environ.get("SUPABASE_POOLER_MODE", "transaction").lower()
    port = os.environ.get("SUPABASE_POOLER_PORT", "6543")

    parsed = urlparse(pooler_url) if pooler_url else None
    hostname = None
    if parsed and parsed.hostname:
        hostname = parsed.hostname
        username = username or parsed.username
        if parsed.path and parsed.path.strip("/"):
            db_name = parsed.path.strip("/")
        if parsed.port:
            port = str(parsed.port)
        if parsed.password:
            password = parsed.password
    elif pooler_host:
        hostname = pooler_host

    if pooler_mode == "transaction":
        port = "6543"
    if not hostname or not username or not password:
        return None

    netloc = f"{username}:{password}@{hostname}:{port}"
    query = urlencode({"sslmode": sslmode})
    return f"postgresql://{netloc}/{db_name}?{query}"


def seed_database_env() -> None:
    url = build_pooler_database_url()
    if url:
        os.environ["DATABASE_URL"] = url


def normalize_supabase_passwords() -> None:
    pooler_user = os.environ.get("SUPABASE_POOLER_USER", "")
    if pooler_user.startswith("sidebar_app") and os.environ.get("SUPABASE_POSTGRES_PSWD"):
        os.environ.setdefault("SUPABASE_APP_PSWD", os.environ["SUPABASE_POSTGRES_PSWD"])


def ensure_supabase_password(*, force: bool = False) -> None:
    if not force and (
        os.environ.get("SUPABASE_APP_PSWD") or os.environ.get("SUPABASE_POSTGRES_PSWD")
    ):
        return
    password = getpass.getpass("Supabase DB password: ").strip()
    if not password:
        raise RuntimeError("Supabase DB password is required to run this migration.")
    os.environ["SUPABASE_APP_PSWD"] = password


def ensure_database_config(*, force_prompt: bool = False) -> None:
    if os.environ.get("DATABASE_URL"):
        parsed = urlparse(os.environ["DATABASE_URL"])
        logging.info(
            "Using database host=%s port=%s user=%s",
            parsed.hostname,
            parsed.port,
            parsed.username,
        )
        return
    ensure_supabase_password(force=force_prompt)
    seed_database_env()
    if os.environ.get("DATABASE_URL"):
        return
    raise RuntimeError("Failed to build DATABASE_URL from Supabase settings.")


def setup_environment(args: argparse.Namespace) -> None:
    load_env_file(REPO_ROOT / ".env.local")
    load_env_file(REPO_ROOT / ".env")
    load_env_file(BACKEND_ROOT / ".env.local")
    load_env_file(BACKEND_ROOT / ".env")
    load_doppler_env()
    normalize_supabase_passwords()

    if args.database_url:
        os.environ["DATABASE_URL"] = args.database_url
        ensure_database_config()
    elif args.supabase:
        os.environ.pop("DATABASE_URL", None)
        ensure_supabase_password(force=True)
        seed_database_env()
        ensure_database_config()
    else:
        ensure_database_config()

    os.environ.setdefault("ANTHROPIC_API_KEY", "local-dev-placeholder")

    if str(BACKEND_ROOT) not in sys.path:
        sys.path.insert(0, str(BACKEND_ROOT))

logger = logging.getLogger(__name__)


def parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    value = value.strip().lower()
    if value in {"true", "1", "yes", "y"}:
        return True
    if value in {"false", "0", "no", "n"}:
        return False
    raise ValueError(f"Invalid boolean value: {value}")


def iter_websites(
    db,
    user_id: str,
    *,
    include_deleted: bool,
    limit: Optional[int],
    pinned: bool | None,
) -> list["Website"]:
    from api.schemas.filters import WebsiteFilters
    from api.services.websites_service import WebsitesService

    filters = WebsiteFilters(pinned=pinned)
    websites = list(
        WebsitesService.list_websites(
            db, user_id, filters, include_deleted=include_deleted
        )
    )
    websites.sort(key=lambda item: item.created_at)
    if limit:
        websites = websites[:limit]
    return websites


if TYPE_CHECKING:
    from api.models.website import Website


def migrate_websites(
    user_id: str,
    *,
    include_deleted: bool,
    limit: Optional[int],
    dry_run: bool,
    stop_on_error: bool,
    pinned: bool | None,
) -> None:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.web_save_parser import ParsedPage, parse_url_local
    from api.services.websites_service import WebsitesService

    db = SessionLocal()
    set_session_user_id(db, user_id)
    websites = iter_websites(
        db,
        user_id,
        include_deleted=include_deleted,
        limit=limit,
        pinned=pinned,
    )
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
    parser.add_argument(
        "--supabase",
        action="store_true",
        help="Prompt for Supabase password and rebuild DATABASE_URL.",
    )
    parser.add_argument(
        "--database-url",
        help="Explicit DATABASE_URL to use for this run.",
    )
    parser.add_argument("--limit", type=int, default=None, help="Limit number of websites.")
    parser.add_argument("--include-deleted", action="store_true", help="Include soft-deleted records.")
    parser.add_argument("--pinned", default=None, help="true or false to filter pinned.")
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
    setup_environment(args)

    from api.db.session import SessionLocal, set_session_user_id
    from api.models.website import Website
    from api.schemas.filters import WebsiteFilters
    from api.services.web_save_parser import ParsedPage, parse_url_local
    from api.services.websites_service import WebsitesService
    migrate_websites(
        args.user_id,
        include_deleted=args.include_deleted,
        limit=args.limit,
        dry_run=args.dry_run,
        stop_on_error=args.stop_on_error,
        pinned=parse_bool(args.pinned),
    )


if __name__ == "__main__":
    main()
