#!/usr/bin/env python3
"""Archive Note.

Archive or unarchive a note in the database.
"""

import argparse
import json
import sys
import uuid
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_service import NotesService
except Exception:
    SessionLocal = None
    NotesService = None


def parse_bool(value: str) -> bool:
    return value.lower() in {"true", "1", "yes", "y"}


def archive_note_database(user_id: str, note_id: str, archived: bool) -> dict:
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        folder = "Archive" if archived else ""
        note = NotesService.update_folder(db, user_id, uuid.UUID(note_id), folder)
        metadata = note.metadata_ or {}
        current_folder = metadata.get("folder", "")
        return {
            "id": str(note.id),
            "archived": current_folder == "Archive" or current_folder.startswith("Archive/"),
            "folder": current_folder,
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Archive or unarchive a note")
    parser.add_argument("note_id", help="Note UUID")
    parser.add_argument("--archived", default="true", help="true or false")
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")
        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = archive_note_database(args.user_id, args.note_id, parse_bool(args.archived))
        print(json.dumps({"success": True, "data": result}, indent=2))
        sys.exit(0)
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
