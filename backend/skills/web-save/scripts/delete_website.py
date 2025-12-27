#!/usr/bin/env python3
"""
Delete Website

Soft delete a website in the database.
"""

import argparse
import json
import sys
import uuid
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.websites_service import WebsitesService
except Exception:
    SessionLocal = None
    WebsitesService = None


def delete_website_database(user_id: str, website_id: str) -> dict:
    if SessionLocal is None or WebsitesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        deleted = WebsitesService.delete_website(db, user_id, uuid.UUID(website_id))
        if not deleted:
            raise ValueError("Website not found")
        return {"id": website_id}
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete a website")
    parser.add_argument("website_id", help="Website UUID")
    parser.add_argument(
        "--database",
        action="store_true",
        help="Delete from database"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results in JSON format"
    )
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = delete_website_database(args.user_id, args.website_id)

        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
