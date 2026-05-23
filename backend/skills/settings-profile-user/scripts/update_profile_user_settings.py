#!/usr/bin/env python3
"""Update profile details and preference fields for a user."""

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

TEXT_FIELDS = (
    "communication_style",
    "working_relationship",
    "name",
    "job_title",
    "employer",
    "gender",
    "pronouns",
    "location",
)

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


def _parse_date(value: str) -> date:
    """Parse an ISO date from YYYY-MM-DD input."""
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("date_of_birth must use YYYY-MM-DD format") from exc


def update_profile_user_settings(
    user_id: str,
    *,
    communication_style: str | None,
    working_relationship: str | None,
    name: str | None,
    job_title: str | None,
    employer: str | None,
    date_of_birth: str | None,
    clear_date_of_birth: bool,
    gender: str | None,
    pronouns: str | None,
    location: str | None,
) -> dict[str, Any]:
    """Update one or more profile details and preference fields."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    updates: dict[str, Any] = {}
    raw_values = {
        "communication_style": communication_style,
        "working_relationship": working_relationship,
        "name": name,
        "job_title": job_title,
        "employer": employer,
        "gender": gender,
        "pronouns": pronouns,
        "location": location,
    }

    for field_name in TEXT_FIELDS:
        field_value = raw_values[field_name]
        if field_value is not None:
            updates[field_name] = field_value

    if date_of_birth and clear_date_of_birth:
        raise ValueError("date_of_birth and clear_date_of_birth cannot both be set")
    if date_of_birth is not None:
        updates["date_of_birth"] = _parse_date(date_of_birth)
    elif clear_date_of_birth:
        updates["date_of_birth"] = None

    if not updates:
        raise ValueError("At least one profile or user field must be provided")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        updated_payload = SettingsService.update_settings(db, user_id, updates)
        return {
            "settings": _serialize_payload(updated_payload),
            "updated_fields": sorted(updates.keys()),
        }
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Update profile and user settings")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--communication-style", dest="communication_style")
    parser.add_argument("--working-relationship", dest="working_relationship")
    parser.add_argument("--name")
    parser.add_argument("--job-title", dest="job_title")
    parser.add_argument("--employer")
    parser.add_argument("--date-of-birth", "--date_of_birth", dest="date_of_birth")
    parser.add_argument("--clear-date-of-birth", action="store_true")
    parser.add_argument("--gender")
    parser.add_argument("--pronouns")
    parser.add_argument("--location")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = update_profile_user_settings(
            args.user_id,
            communication_style=args.communication_style,
            working_relationship=args.working_relationship,
            name=args.name,
            job_title=args.job_title,
            employer=args.employer,
            date_of_birth=args.date_of_birth,
            clear_date_of_birth=args.clear_date_of_birth,
            gender=args.gender,
            pronouns=args.pronouns,
            location=args.location,
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
