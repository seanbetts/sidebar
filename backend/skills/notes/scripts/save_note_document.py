#!/usr/bin/env python3
# ruff: noqa: D103, T201
"""Save semantic note documents.

Create or update notes stored in the database using canonical note documents.
"""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path
from typing import Any

# Add backend to sys.path for database mode.
BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_document_types import validate_note_document
    from api.services.notes_service import NotesService
except Exception:
    SessionLocal = None
    NotesService = None


def _parse_document_argument(document_json: str) -> dict[str, Any]:
    """Parse the CLI document argument into a JSON object."""
    try:
        payload = json.loads(document_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"document must be valid JSON: {exc.msg}") from exc
    if not isinstance(payload, dict):
        raise ValueError("document must be a JSON object")
    return payload


def save_note_document_database(
    user_id: str,
    document: dict[str, Any],
    mode: str = "create",
    folder: str | None = None,
    note_id: str | None = None,
    tags: list[str] | None = None,
) -> dict[str, Any]:
    """Create or update a note from a semantic document."""
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        if mode == "create":
            note = NotesService.create_note(
                db,
                user_id,
                document=document,
                folder=folder or "",
                tags=tags,
            )
            return {
                "id": str(note.id),
                "title": note.title,
                "folder": note.folder_path or "",
            }

        if mode not in {"update", "append"}:
            raise ValueError("Database mode supports create, update, or append only")
        if not note_id:
            raise ValueError("note_id is required for update and append modes")

        resolved_document = document
        if mode == "append":
            existing_note = NotesService.get_note(
                db,
                user_id,
                uuid.UUID(note_id),
                mark_opened=False,
            )
            if existing_note is None:
                raise ValueError("Note not found")
            existing_document = validate_note_document(existing_note.document)
            appended_document = validate_note_document(
                document,
                require_title_block=False,
            )
            resolved_document = {
                "version": existing_document["version"],
                "blocks": [
                    *existing_document["blocks"],
                    *appended_document["blocks"],
                ],
            }

        note = NotesService.update_note(
            db,
            user_id,
            uuid.UUID(note_id),
            document=resolved_document,
        )
        return {
            "id": str(note.id),
            "title": note.title,
            "folder": note.folder_path or "",
        }
    finally:
        db.close()


def main() -> None:
    """Run the semantic document save script."""
    parser = argparse.ArgumentParser(
        description="Save a note semantic document",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create a new note from a semantic document
  %(prog)s --document '{"version":1,"blocks":[{"type":"paragraph","content":[{"text":"Hello","marks":[]}]}]}' --database --user-id user-1

  # Update an existing note
  %(prog)s --document '{"version":1,"blocks":[{"type":"paragraph","content":[{"text":"Updated","marks":["bold"]}]}]}' \\
    --mode update --note-id <uuid> --database --user-id user-1

  # Append blocks to an existing note
  %(prog)s --document '{"version":1,"blocks":[{"type":"paragraph","content":[{"text":"Appended","marks":["italic"]}]}]}' \\
    --mode append --note-id <uuid> --database --user-id user-1
        """,
    )

    parser.add_argument("--document", required=True, help="Note semantic document JSON")
    parser.add_argument(
        "--mode",
        default="create",
        choices=["create", "update", "append"],
        help="Operation mode (default: create)",
    )
    parser.add_argument("--folder", help="Subfolder in notes/")
    parser.add_argument("--tags", help="Comma-separated tag list")
    parser.add_argument("--note-id", help="Note UUID for update mode")
    parser.add_argument(
        "--json", action="store_true", help="Output results in JSON format"
    )
    parser.add_argument("--database", action="store_true", help="Save to database")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")
        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = save_note_document_database(
            user_id=args.user_id,
            document=_parse_document_argument(args.document),
            mode=args.mode,
            folder=args.folder,
            note_id=args.note_id,
            tags=args.tags.split(",") if args.tags else None,
        )

        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)
    except ValueError as exc:
        error_output = {"success": False, "error": str(exc)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        error_output = {"success": False, "error": f"Unexpected error: {str(exc)}"}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
