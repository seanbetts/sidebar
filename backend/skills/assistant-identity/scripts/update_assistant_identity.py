#!/usr/bin/env python3
"""Update assistant identity fields for a user."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.settings_service import SettingsService
except Exception:
    SessionLocal = None
    SettingsService = None

IDENTITY_FIELDS = ("name", "tone", "values", "boundaries")


def update_assistant_identity(
    user_id: str,
    *,
    name: str | None,
    tone: str | None,
    values: str | None,
    boundaries: str | None,
    reason: str | None,
) -> dict:
    """Update one or more assistant identity fields."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    requested_updates = {
        "name": name,
        "tone": tone,
        "values": values,
        "boundaries": boundaries,
    }
    changed_fields = [
        field_name
        for field_name, field_value in requested_updates.items()
        if field_value is not None
    ]
    if not changed_fields:
        raise ValueError("At least one identity field must be provided")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        current_payload = SettingsService.get_settings(db, user_id)
        current_identity = current_payload.get("assistant_identity") or {}

        merged_identity = {
            field_name: current_identity.get(field_name)
            for field_name in IDENTITY_FIELDS
        }
        for field_name in changed_fields:
            merged_identity[field_name] = requested_updates[field_name]

        updated_payload = SettingsService.update_agent_settings(
            db,
            user_id,
            {"assistant_identity": merged_identity},
            reason=reason,
        )
        return {
            "assistant_identity": updated_payload.get("assistant_identity", {}),
            "assistant_identity_meta": updated_payload.get("assistant_identity_meta"),
            "updated_fields": changed_fields,
        }
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Update assistant identity")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--name", help="Assistant name")
    parser.add_argument("--tone", help="Assistant tone")
    parser.add_argument("--values", help="Assistant values")
    parser.add_argument("--boundaries", help="Assistant boundaries")
    parser.add_argument("--reason", help="Reason for updating assistant identity")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = update_assistant_identity(
            args.user_id,
            name=args.name,
            tone=args.tone,
            values=args.values,
            boundaries=args.boundaries,
            reason=args.reason,
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
