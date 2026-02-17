#!/usr/bin/env python3
"""Reset assistant soul settings to defaults."""

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


def reset_assistant_soul(user_id: str, *, reason: str | None) -> dict:
    """Reset assistant soul payload for a user."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        updated_payload = SettingsService.update_agent_settings(
            db,
            user_id,
            {"assistant_soul": None},
            reason=reason,
        )
        return {
            "assistant_soul": updated_payload.get("assistant_soul", {}),
            "assistant_soul_meta": updated_payload.get("assistant_soul_meta"),
            "reset": True,
        }
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Reset assistant soul")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--reason", help="Reason for resetting assistant soul")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = reset_assistant_soul(args.user_id, reason=args.reason)
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
