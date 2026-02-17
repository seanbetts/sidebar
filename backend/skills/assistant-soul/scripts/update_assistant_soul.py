#!/usr/bin/env python3
"""Update assistant soul fields for a user."""

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

SOUL_FIELDS = (
    "purpose",
    "operating_principles",
    "adaptation_policy",
    "success_signals",
)


def update_assistant_soul(
    user_id: str,
    *,
    purpose: str | None,
    operating_principles: str | None,
    adaptation_policy: str | None,
    success_signals: str | None,
    reason: str | None,
) -> dict:
    """Update one or more assistant soul fields."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    requested_updates = {
        "purpose": purpose,
        "operating_principles": operating_principles,
        "adaptation_policy": adaptation_policy,
        "success_signals": success_signals,
    }
    changed_fields = [
        field_name
        for field_name, field_value in requested_updates.items()
        if field_value is not None
    ]
    if not changed_fields:
        raise ValueError("At least one soul field must be provided")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        current_payload = SettingsService.get_settings(db, user_id)
        current_soul = current_payload.get("assistant_soul") or {}

        merged_soul = {
            field_name: current_soul.get(field_name) for field_name in SOUL_FIELDS
        }
        for field_name in changed_fields:
            merged_soul[field_name] = requested_updates[field_name]

        updated_payload = SettingsService.update_agent_settings(
            db,
            user_id,
            {"assistant_soul": merged_soul},
            reason=reason,
        )
        return {
            "assistant_soul": updated_payload.get("assistant_soul", {}),
            "assistant_soul_meta": updated_payload.get("assistant_soul_meta"),
            "updated_fields": changed_fields,
        }
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Update assistant soul")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--purpose", help="Assistant soul purpose")
    parser.add_argument(
        "--operating-principles",
        "--operating_principles",
        dest="operating_principles",
        help="Assistant soul operating principles",
    )
    parser.add_argument(
        "--adaptation-policy",
        "--adaptation_policy",
        dest="adaptation_policy",
        help="Assistant soul adaptation policy",
    )
    parser.add_argument(
        "--success-signals",
        "--success_signals",
        dest="success_signals",
        help="Assistant soul success signals",
    )
    parser.add_argument("--reason", help="Reason for updating assistant soul")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = update_assistant_soul(
            args.user_id,
            purpose=args.purpose,
            operating_principles=args.operating_principles,
            adaptation_policy=args.adaptation_policy,
            success_signals=args.success_signals,
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
