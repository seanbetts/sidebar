#!/usr/bin/env python3
"""Read Website

Fetch a website from the database.
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


def read_website_database(user_id: str, website_id: str) -> dict:
    if SessionLocal is None or WebsitesService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()

    set_session_user_id(db, user_id)
    try:
        website = WebsitesService.get_website(
            db, user_id, uuid.UUID(website_id), mark_opened=True
        )
        if not website:
            raise ValueError("Website not found")
        metadata = website.metadata_ or {}
        return {
            "id": str(website.id),
            "title": website.title,
            "content": website.content,
            "url": website.url,
            "url_full": website.url_full,
            "domain": website.domain,
            "source": website.source,
            "saved_at": website.saved_at.isoformat() if website.saved_at else None,
            "published_at": website.published_at.isoformat()
            if website.published_at
            else None,
            "pinned": bool(metadata.get("pinned")),
            "archived": bool(metadata.get("archived")),
            "created_at": website.created_at.isoformat()
            if website.created_at
            else None,
            "updated_at": website.updated_at.isoformat()
            if website.updated_at
            else None,
            "last_opened_at": website.last_opened_at.isoformat()
            if website.last_opened_at
            else None,
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Read a website by ID")
    parser.add_argument("website_id", help="Website UUID")
    parser.add_argument("--database", action="store_true", help="Use database mode")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--user-id", help="User id for database access")

    args = parser.parse_args()

    try:
        if not args.database:
            raise ValueError("Database mode required")

        if not args.user_id:
            raise ValueError("user_id is required for database mode")

        result = read_website_database(args.user_id, args.website_id)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
