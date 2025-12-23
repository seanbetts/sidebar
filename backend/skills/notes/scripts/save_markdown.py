#!/usr/bin/env python3
"""
Save Markdown Note

Create, update, or append markdown notes with automatic organization and metadata.
"""

import sys
import uuid
import json
import os
import argparse
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List

# Add backend to sys.path for database mode.
BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

# Base workspace directory
WORKSPACE_BASE = Path(os.getenv("WORKSPACE_BASE", "/workspace"))
NOTES_BASE = WORKSPACE_BASE / "notes"

try:
    from api.db.session import SessionLocal
    from api.services.notes_service import NotesService
except Exception:
    SessionLocal = None
    NotesService = None


def save_markdown(
    title: str,
    content: str,
    mode: str = "create",
    folder: str = None,
    tags: List[str] = None
) -> Dict[str, Any]:
    """
    Save markdown note with frontmatter.

    Modes:
    - create: Create new note (fails if exists)
    - update: Replace existing note (fails if doesn't exist)
    - append: Append to existing note (creates if doesn't exist)

    Args:
        title: Note title
        content: Note content (markdown)
        mode: Operation mode (create/update/append)
        folder: Optional subfolder in notes/
        tags: Optional list of tags

    Returns:
        Dictionary with operation result

    Raises:
        ValueError: If mode is invalid
        FileExistsError: If mode is create and file exists
        FileNotFoundError: If mode is update and file doesn't exist
    """
    # Validate mode
    if mode not in ["create", "update", "append"]:
        raise ValueError(f"Invalid mode: {mode}. Must be create, update, or append")

    # Auto-organize by date if no folder specified
    if not folder:
        today = datetime.now()
        folder = f"{today.year}/{today.strftime('%B')}"

    # Create directory
    note_dir = NOTES_BASE / folder
    note_dir.mkdir(parents=True, exist_ok=True)

    # Generate filename from title (lowercase, replace spaces with hyphens)
    filename = f"{title.lower().replace(' ', '-')}.md"
    filepath = note_dir / filename

    # Check file existence based on mode
    exists = filepath.exists()

    if mode == "create" and exists:
        raise FileExistsError(f"Note already exists: {filepath.relative_to(WORKSPACE_BASE)}")
    elif mode == "update" and not exists:
        raise FileNotFoundError(f"Note not found: {filepath.relative_to(WORKSPACE_BASE)}")

    # Handle different modes
    if mode == "append" and exists:
        # Append to existing note (no frontmatter, just content)
        with open(filepath, 'a', encoding='utf-8') as f:
            f.write("\n\n")
            f.write(content)
        action = "appended"
    else:
        # Create or update (replace with full frontmatter)
        # Build frontmatter
        metadata = {
            "title": title,
            "date": datetime.now().strftime("%Y-%m-%d"),
        }
        if tags:
            metadata["tags"] = tags

        with open(filepath, 'w', encoding='utf-8') as f:
            # Write YAML frontmatter
            f.write("---\n")
            for key, value in metadata.items():
                if isinstance(value, list):
                    f.write(f"{key}:\n")
                    for item in value:
                        f.write(f"  - {item}\n")
                else:
                    f.write(f"{key}: {value}\n")
            f.write("---\n\n")

            # Write title and content
            f.write(f"# {title}\n\n")
            f.write(content)

        action = "created" if not exists else "updated"

    return {
        'path': str(filepath.relative_to(WORKSPACE_BASE)),
        'title': title,
        'mode': mode,
        'action': action,
        'size': filepath.stat().st_size
    }


def save_markdown_database(
    title: str,
    content: str,
    mode: str = "create",
    folder: str = None,
    note_id: str = None,
) -> Dict[str, Any]:
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    try:
        if mode == "update":
            if not note_id:
                raise ValueError("note_id is required for update mode")
            note = NotesService.update_note(db, uuid.UUID(note_id), content, title=title)
            return {"id": str(note.id), "title": note.title}

        if mode != "create":
            raise ValueError("Database mode supports create or update only")

        note = NotesService.create_note(
            db,
            content,
            title=title,
            folder=folder or "",
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
  %(prog)s "Meeting Notes" --content "Discussion points" --tags "meeting,project"

  # Update existing note
  %(prog)s "Meeting Notes" --content "New content" --mode update

  # Append to existing note
  %(prog)s "Meeting Notes" --content "Additional info" --mode append

  # Custom folder
  %(prog)s "Personal Note" --content "Content" --folder "personal"
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
        help='Comma-separated tags'
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
        help='Save to database instead of filesystem'
    )

    args = parser.parse_args()

    # Parse tags if provided
    tags = args.tags.split(",") if args.tags else None

    try:
        if args.database:
            result = save_markdown_database(
                args.title,
                args.content,
                args.mode,
                args.folder,
                args.note_id,
            )
        else:
            result = save_markdown(
                args.title,
                args.content,
                args.mode,
                args.folder,
                tags
            )

        output = {
            'success': True,
            'data': result
        }
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except (ValueError, FileExistsError, FileNotFoundError) as e:
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
