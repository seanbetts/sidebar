#!/usr/bin/env python3
"""
List Notes

List notes with filters from the database.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_service import NotesService
    from api.schemas.filters import NoteFilters
except Exception:
    SessionLocal = None
    NotesService = None
    NoteFilters = None


def parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    return value.lower() in {"true", "1", "yes", "y"}


def parse_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"Invalid datetime: {value}") from exc


def list_notes_database(args: argparse.Namespace) -> dict:
    if SessionLocal is None or NotesService is None or NoteFilters is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, args.user_id)
    try:
        filters = NoteFilters(
            folder=args.folder,
            pinned=parse_bool(args.pinned),
            archived=parse_bool(args.archived),
            created_after=parse_datetime(args.created_after),
            created_before=parse_datetime(args.created_before),
            updated_after=parse_datetime(args.updated_after),
            updated_before=parse_datetime(args.updated_before),
            opened_after=parse_datetime(args.opened_after),
            opened_before=parse_datetime(args.opened_before),
            title_search=args.title,
        )
        notes = NotesService.list_notes(db, args.user_id, filters)
        items = []
        for note in notes:
            metadata = note.metadata_ or {}
            folder = metadata.get("folder", "")
            archived = folder == "Archive" or folder.startswith("Archive/")
            items.append({
                "id": str(note.id),
                "title": note.title,
                "folder": folder,
                "pinned": bool(metadata.get("pinned")),
                "archived": archived,
                "created_at": note.created_at.isoformat() if note.created_at else None,
                "updated_at": note.updated_at.isoformat() if note.updated_at else None,
                "last_opened_at": note.last_opened_at.isoformat() if note.last_opened_at else None,
            })

        return {"items": items, "count": len(items)}
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="List notes")
    parser.add_argument("--folder", help="Folder path filter")
    parser.add_argument("--pinned", help="true or false")
    parser.add_argument("--archived", help="true or false")
    parser.add_argument("--created-after", help="ISO datetime filter")
    parser.add_argument("--created-before", help="ISO datetime filter")
    parser.add_argument("--updated-after", help="ISO datetime filter")
    parser.add_argument("--updated-before", help="ISO datetime filter")
    parser.add_argument("--opened-after", help="ISO datetime filter")
    parser.add_argument("--opened-before", help="ISO datetime filter")
    parser.add_argument("--title", help="Search by title")
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = list_notes_database(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
