#!/usr/bin/env python3
"""Rename a conversation title."""

from __future__ import annotations

import argparse
import json
import sys
import uuid
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


def rename_conversation(args: argparse.Namespace) -> dict:
    """Rename a conversation by ID."""
    if SessionLocal is None or ConversationService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)
    try:
        conversation = ConversationService.rename_conversation(
            db,
            args.user_id,
            uuid.UUID(args.conversation_id),
            args.new_name,
        )
        return conversation_payload(conversation)
    finally:
        db.close()


def main() -> None:
    """Run the conversation rename CLI."""
    parser = argparse.ArgumentParser(description="Rename a conversation")
    parser.add_argument("conversation_id", help="Conversation UUID")
    parser.add_argument("--new-name", required=True, help="New conversation title")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = rename_conversation(args)
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
