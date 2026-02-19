#!/usr/bin/env python3
"""Return profile and user settings fields for a user."""

from __future__ import annotations

import argparse
import json
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


def get_profile_user_settings(user_id: str) -> dict[str, Any]:
    """Fetch profile and user settings fields for a user."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        settings_payload = SettingsService.get_settings(db, user_id)
        return {"settings": _serialize_payload(settings_payload)}
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Get profile and user settings")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = get_profile_user_settings(args.user_id)
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
