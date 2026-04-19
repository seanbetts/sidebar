#!/usr/bin/env python3
"""Preview or clear failed plist sidecar uploads."""

from __future__ import annotations

import argparse
import sys
from collections.abc import Iterable
from pathlib import Path

SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from .db_env import setup_environment  # noqa: E402

DEFAULT_MAX_SIZE_BYTES = 4 * 1024


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments for plist upload cleanup."""
    parser = argparse.ArgumentParser(
        description="Preview or clear failed UUID-named plist uploads."
    )
    parser.add_argument(
        "--user-id",
        help="Only inspect or clean rows for this user ID.",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Apply the cleanup instead of running in dry-run mode.",
    )
    parser.add_argument(
        "--max-size-bytes",
        type=int,
        default=DEFAULT_MAX_SIZE_BYTES,
        help="Maximum file size to match. Defaults to 4096 bytes.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=500,
        help="Maximum number of candidate rows to inspect.",
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


def _session_factory():
    """Return the configured SQLAlchemy session factory."""
    from api.db.session import SessionLocal

    return SessionLocal


def _cleanup_service():
    """Return the cleanup service after env configuration is loaded."""
    from api.services.plist_upload_cleanup_service import PlistUploadCleanupService

    return PlistUploadCleanupService


def _set_session_user_id(db, user_id: str) -> None:
    """Attach the user context to the database session."""
    from api.db.session import set_session_user_id

    set_session_user_id(db, user_id)


def _set_retention_worker_scope(db, enabled: bool) -> None:
    """Enable cross-user cleanup scope on the session when needed."""
    from api.db.session import set_retention_worker_scope

    set_retention_worker_scope(db, enabled=enabled)


def main(argv: Iterable[str] | None = None) -> int:
    """Run the plist upload cleanup command."""
    args = parse_args(argv)
    setup_environment(database_url=args.database_url, supabase=args.supabase)
    cleanup_service = _cleanup_service()
    session_factory = _session_factory()
    with session_factory() as db:
        if args.user_id:
            _set_session_user_id(db, args.user_id)
        else:
            _set_retention_worker_scope(db, enabled=True)
        summary = cleanup_service.cleanup_candidates(
            db,
            user_id=args.user_id,
            dry_run=not args.yes,
            max_size_bytes=args.max_size_bytes,
            limit=args.limit,
        )

    print(
        f"dry_run={summary.dry_run} "
        f"user_id={args.user_id or 'all'} "
        f"matched_files={summary.matched_files} "
        f"deleted_files={summary.deleted_files} "
        f"matched_users={summary.matched_users}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
