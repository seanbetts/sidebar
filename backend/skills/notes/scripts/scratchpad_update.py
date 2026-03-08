#!/usr/bin/env python3
# ruff: noqa: D103, D415, T201
"""Scratchpad Update.

Update the scratchpad content by fixed title.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_document_types import (
        NOTE_DOCUMENT_VERSION,
        note_document_from_plain_text,
        validate_note_document,
    )
    from api.services.notes_service import NotesService
except Exception:
    SessionLocal = None
    NotesService = None

SCRATCHPAD_TITLE = "✏️ Scratchpad"
LEGACY_SCRATCHPAD_TITLE = f"# {SCRATCHPAD_TITLE}"


def _parse_document_argument(document_json: str) -> dict[str, Any]:
    try:
        payload = json.loads(document_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"document must be valid JSON: {exc.msg}") from exc
    if not isinstance(payload, dict):
        raise ValueError("document must be a JSON object")
    return payload


def _title_only_document() -> dict[str, Any]:
    return {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            {
                "type": "paragraph",
                "content": [{"text": SCRATCHPAD_TITLE, "marks": []}],
            }
        ],
    }


def _scratchpad_document(document: dict[str, Any]) -> dict[str, Any]:
    validated = validate_note_document(document)
    return {
        "version": NOTE_DOCUMENT_VERSION,
        "blocks": [
            *_title_only_document()["blocks"],
            *validated["blocks"],
        ],
    }


def _legacy_body_plain_text(plain_text: str | None) -> str:
    if not plain_text:
        return ""
    trimmed = plain_text.lstrip()
    if not trimmed.startswith(LEGACY_SCRATCHPAD_TITLE):
        return plain_text.strip()
    lines = trimmed.splitlines()
    if not lines:
        return ""
    return "\n".join(lines[1:]).lstrip("\n").strip()


def _migrate_legacy_note_if_needed(db, user_id: str, note) -> Any:
    if not note or note.title != LEGACY_SCRATCHPAD_TITLE:
        return note
    body_plain_text = _legacy_body_plain_text(note.plain_text)
    body_document = (
        {"version": NOTE_DOCUMENT_VERSION, "blocks": []}
        if not body_plain_text
        else note_document_from_plain_text(body_plain_text)
    )
    return NotesService.update_note(
        db,
        user_id,
        note.id,
        document=_scratchpad_document(body_document),
    )


def update_scratchpad(user_id: str, document: dict[str, Any]) -> dict:
    if SessionLocal is None or NotesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        note = NotesService.get_note_by_title(
            db, user_id, SCRATCHPAD_TITLE, mark_opened=False
        )
        if not note:
            note = NotesService.get_note_by_title(
                db,
                user_id,
                LEGACY_SCRATCHPAD_TITLE,
                mark_opened=False,
            )
            note = _migrate_legacy_note_if_needed(db, user_id, note)
        if not note:
            note = NotesService.create_note(
                db,
                user_id,
                document=_title_only_document(),
                folder="",
            )

        updated = NotesService.update_note(
            db,
            user_id,
            note.id,
            document=_scratchpad_document(document),
        )

        return {"id": str(updated.id), "title": updated.title}
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Update scratchpad content")
    parser.add_argument("--document", required=True, help="Scratchpad document JSON")
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = update_scratchpad(
            args.user_id,
            _parse_document_argument(args.document),
        )
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)
    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
