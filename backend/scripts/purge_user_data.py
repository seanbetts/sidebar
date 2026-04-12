#!/usr/bin/env python3
"""Purge all stored data for a single user."""

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

from api.services.user_data_purge_service import UserDataPurgeService  # noqa: E402


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments for the purge script."""
    parser = argparse.ArgumentParser(description="Purge all data for a user.")
    parser.add_argument("--user-id", required=True, help="User ID to purge.")
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Confirm that the purge should run.",
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


def _set_session_user_id(db, user_id: str) -> None:
    """Attach the user context to the database session."""
    from api.db.session import set_session_user_id

    set_session_user_id(db, user_id)


def main(argv: Iterable[str] | None = None) -> int:
    """Run the purge command."""
    args = parse_args(argv)
    if not args.yes:
        print("Refusing to purge user data without --yes.")
        return 2

    setup_environment(database_url=args.database_url, supabase=args.supabase)
    session_factory = _session_factory()
    with session_factory() as db:
        _set_session_user_id(db, args.user_id)
        summary = UserDataPurgeService.purge_user_data(db, args.user_id)

    print(
        f"Purged user_id={args.user_id} "
        f"total_rows_deleted={summary.total_rows_deleted} "
        f"storage_objects_deleted={summary.storage_objects_deleted}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
