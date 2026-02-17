#!/usr/bin/env python3
"""Download Note.

Prepare note markdown content for download/export.
"""

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_workspace_service import NotesWorkspaceService
except Exception:
    SessionLocal = None
    NotesWorkspaceService = None


def download_note_database(user_id: str, note_id: str) -> dict:
    if SessionLocal is None or NotesWorkspaceService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        return NotesWorkspaceService.download_note(db, user_id, note_id)
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Export note markdown")
    parser.add_argument("note_id", help="Note UUID")
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")
        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = download_note_database(args.user_id, args.note_id)
        print(json.dumps({"success": True, "data": result}, indent=2))
        sys.exit(0)
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
