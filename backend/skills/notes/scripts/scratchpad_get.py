#!/usr/bin/env python3
"""
Scratchpad Get

Fetch the scratchpad note by fixed title.
"""

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_service import NotesService
except Exception:
    SessionLocal = None
    NotesService = None

SCRATCHPAD_TITLE = "✏️ Scratchpad"


def get_scratchpad(user_id: str) -> dict:
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        note = NotesService.get_note_by_title(db, user_id, SCRATCHPAD_TITLE, mark_opened=True)
        if not note:
            note = NotesService.create_note(
                db,
                user_id,
                content=f"# {SCRATCHPAD_TITLE}\n\n",
                title=SCRATCHPAD_TITLE,
                folder="",
            )

        return {
            "id": str(note.id),
            "title": note.title,
            "content": note.content,
            "created_at": note.created_at.isoformat() if note.created_at else None,
            "updated_at": note.updated_at.isoformat() if note.updated_at else None,
            "last_opened_at": note.last_opened_at.isoformat() if note.last_opened_at else None,
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Get scratchpad note")
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = get_scratchpad(args.user_id)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)
    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
