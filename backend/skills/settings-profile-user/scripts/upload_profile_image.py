#!/usr/bin/env python3
"""Upload a profile image for a user from a local file path."""

from __future__ import annotations

import argparse
import json
import mimetypes
import sys
from datetime import date
from pathlib import Path
from typing import Any

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.settings_service import SettingsService
except Exception:
    SessionLocal = None
    SettingsService = None

PROFILE_USER_FIELDS = (
    "communication_style",
    "working_relationship",
    "name",
    "job_title",
    "employer",
    "date_of_birth",
    "gender",
    "pronouns",
    "location",
    "profile_image_url",
)


def _serialize_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Serialize date-like values for JSON output."""
    serialized: dict[str, Any] = {}
    for key in PROFILE_USER_FIELDS:
        value = payload.get(key)
        if isinstance(value, date):
            serialized[key] = value.isoformat()
        else:
            serialized[key] = value
    return serialized


def _resolve_content_type(path: Path, content_type: str | None) -> str:
    """Resolve content type from input or filename."""
    if content_type:
        resolved = content_type.strip().lower()
    else:
        guessed, _ = mimetypes.guess_type(path.name)
        resolved = (guessed or "").lower()

    if not resolved.startswith("image/"):
        raise ValueError("content_type must be an image/* MIME type")
    return resolved


def upload_profile_image(
    user_id: str,
    *,
    path: str,
    content_type: str | None,
) -> dict[str, Any]:
    """Upload a profile image for a user."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    file_path = Path(path).expanduser()
    if not file_path.is_file():
        raise ValueError("path must point to an existing file")

    resolved_content_type = _resolve_content_type(file_path, content_type)
    contents = file_path.read_bytes()

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        upload_result = SettingsService.upload_profile_image(
            db,
            user_id,
            content_type=resolved_content_type,
            contents=contents,
            filename=file_path.name,
        )
        settings_payload = SettingsService.get_settings(db, user_id)
        return {
            "profile_image_url": upload_result.get("profile_image_url"),
            "settings": _serialize_payload(settings_payload),
        }
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Upload profile image")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--path", required=True, help="Path to image file")
    parser.add_argument(
        "--content-type",
        dest="content_type",
        help="Optional MIME type",
    )
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = upload_profile_image(
            args.user_id,
            path=args.path,
            content_type=args.content_type,
        )
        sys.stdout.write(json.dumps({"success": True, "data": result}, indent=2))
        sys.stdout.write("\n")
        sys.exit(0)
    except Exception as exc:
        error_payload = {"success": False, "error": str(exc)}
        sys.stderr.write(json.dumps(error_payload, indent=2))
        sys.stderr.write("\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
