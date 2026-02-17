#!/usr/bin/env python3
"""Return the assistant identity payload for a user."""

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


def get_assistant_identity(user_id: str) -> dict:
    """Fetch the resolved assistant identity for a user."""
    if SessionLocal is None or SettingsService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        settings_payload = SettingsService.get_settings(db, user_id)
        return {
            "assistant_identity": settings_payload.get("assistant_identity", {}),
        }
    finally:
        db.close()


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Get assistant identity")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = get_assistant_identity(args.user_id)
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
