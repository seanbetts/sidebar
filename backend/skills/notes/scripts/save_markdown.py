#!/usr/bin/env python3
"""
Save Markdown Note

Create or update markdown notes stored in the database.
"""

import sys
import uuid
import json
import argparse
from pathlib import Path
from typing import Dict, Any

# Add backend to sys.path for database mode.
BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_service import NotesService
except Exception:
    SessionLocal = None
    NotesService = None


def save_markdown_database(
    user_id: str,
    title: str,
    content: str,
    mode: str = "create",
    folder: str | None = None,
    note_id: str | None = None,
    tags: list[str] | None = None,
) -> Dict[str, Any]:
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        if mode in {"update", "append"}:
            resolved_id = note_id
            if not resolved_id:
                note = NotesService.get_note_by_title(db, user_id, title, mark_opened=False)
                if not note:
                    raise ValueError("note_id is required for update mode")
                resolved_id = str(note.id)
            else:
                note = NotesService.get_note(db, user_id, uuid.UUID(resolved_id), mark_opened=False)

            if not note:
                raise ValueError("note_id is required for update mode")

            updated_content = content
            if mode == "append":
                updated_content = f"{note.content}{content}"

            note = NotesService.update_note(
                db,
                user_id,
                uuid.UUID(resolved_id),
                updated_content,
                title=title,
            )
            return {"id": str(note.id), "title": note.title}

        if mode != "create":
            raise ValueError("Database mode supports create, update, or append only")

        note = NotesService.create_note(
            db,
            user_id,
            content,
            title=title,
            folder=folder or "",
            tags=tags,
        )
        return {
            "id": str(note.id),
            "title": note.title,
            "folder": (note.metadata_ or {}).get("folder", ""),
        }
    finally:
        db.close()


def main():
    """Main entry point for save_markdown script."""
    parser = argparse.ArgumentParser(
        description='Save markdown note with metadata',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create a new note
  %(prog)s "Meeting Notes" --content "Discussion points" --database

  # Update existing note
  %(prog)s "Meeting Notes" --content "New content" --mode update --note-id <uuid> --database

  # Custom folder
  %(prog)s "Personal Note" --content "Content" --folder "personal" --database
        """
    )

    parser.add_argument(
        'title',
        help='Note title'
    )
    parser.add_argument(
        '--content',
        required=True,
        help='Note content (markdown)'
    )
    parser.add_argument(
        '--mode',
        default='create',
        choices=['create', 'update', 'append'],
        help='Operation mode (default: create)'
    )
    parser.add_argument(
        '--folder',
        help='Subfolder in notes/ (default: YYYY/Month)'
    )
    parser.add_argument(
        '--tags',
        help='Comma-separated tag list'
    )
    parser.add_argument(
        '--note-id',
        help='Note UUID for update mode'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )
    parser.add_argument(
        '--database',
        action='store_true',
        help='Save to database'
    )
    parser.add_argument(
        '--user-id',
        help='User id for database access'
    )

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = save_markdown_database(
            args.user_id,
            args.title,
            args.content,
            args.mode,
            args.folder,
            args.note_id,
            args.tags.split(",") if args.tags else None,
        )

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': str(e)
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': f'Unexpected error: {str(e)}'
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
