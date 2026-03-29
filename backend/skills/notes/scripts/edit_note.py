#!/usr/bin/env python3
# ruff: noqa: D103, T201
"""Edit a semantic note with structured block operations."""

from __future__ import annotations

import argparse
import json
import sys
import uuid
from pathlib import Path
from typing import Any

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.notes_edit_service import NotesEditService
except Exception:
    SessionLocal = None
    NotesEditService = None


def _parse_operations_argument(operations_json: str) -> list[dict[str, Any]]:
    """Parse the CLI operations payload into a JSON list."""
    try:
        payload = json.loads(operations_json)
    except json.JSONDecodeError as exc:
        raise ValueError(f"operations must be valid JSON: {exc.msg}") from exc
    if not isinstance(payload, list):
        raise ValueError("operations must be a JSON array")
    if any(not isinstance(item, dict) for item in payload):
        raise ValueError("operations must contain JSON objects")
    return payload


def edit_note_database(
    user_id: str,
    note_id: str,
    expected_updated_at: str,
    operations: list[dict[str, Any]],
) -> dict[str, str]:
    """Apply structured edit operations to an existing note."""
    if SessionLocal is None or NotesEditService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        return NotesEditService.edit_note(
            db,
            user_id,
            uuid.UUID(note_id),
            expected_updated_at=expected_updated_at,
            operations=operations,
        )
    finally:
        db.close()


def main() -> None:
    """Run the structured note edit script."""
    parser = argparse.ArgumentParser(description="Edit a note by structured operations")
    parser.add_argument("--note-id", required=True, help="Note UUID")
    parser.add_argument(
        "--expected-updated-at",
        required=True,
        help="Exact server updated_at from Get Note",
    )
    parser.add_argument(
        "--operations",
        required=True,
        help="JSON array of ordered note edit operations",
    )
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")
        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = edit_note_database(
            user_id=args.user_id,
            note_id=args.note_id,
            expected_updated_at=args.expected_updated_at,
            operations=_parse_operations_argument(args.operations),
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
