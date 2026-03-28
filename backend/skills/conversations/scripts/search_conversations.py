#!/usr/bin/env python3
"""Search conversations by title or visible preview text."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.conversation_service import ConversationService
except Exception:
    SessionLocal = None
    ConversationService = None


def conversation_payload(conversation) -> dict:
    """Convert a conversation model to a JSON-serializable summary."""
    return {
        "id": str(conversation.id),
        "title": conversation.title,
        "titleGenerated": conversation.title_generated,
        "createdAt": conversation.created_at.isoformat(),
        "updatedAt": conversation.updated_at.isoformat(),
        "messageCount": conversation.message_count,
        "firstMessage": conversation.first_message,
    }


def search_conversations(args: argparse.Namespace) -> dict:
    """Search conversations by query."""
    if SessionLocal is None or ConversationService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)
    try:
        conversations = ConversationService.search_conversations(
            db,
            args.user_id,
            args.query,
            limit=args.limit,
        )
        return {
            "query": args.query,
            "conversations": [
                conversation_payload(conversation) for conversation in conversations
            ],
            "count": len(conversations),
        }
    finally:
        db.close()


def main() -> None:
    """Run the conversation search CLI."""
    parser = argparse.ArgumentParser(description="Search conversations")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--limit", type=int, default=10, help="Maximum results")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        if not args.query.strip():
            raise ValueError("Query cannot be empty")
        if args.limit <= 0:
            raise ValueError("Limit must be greater than 0")

        result = search_conversations(args)
        print(json.dumps({"success": True, "data": result}, indent=2))
        sys.exit(0)
    except Exception as exc:
        print(
            json.dumps({"success": False, "error": str(exc)}, indent=2),
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
