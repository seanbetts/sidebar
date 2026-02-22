#!/usr/bin/env python3
"""Submit product feedback as a GitHub issue."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.services.github_issue_service import GitHubIssueService
except Exception:
    GitHubIssueService = None


def submit_feedback(args: argparse.Namespace) -> dict:
    """Submit feedback to GitHub and return API payload."""
    if GitHubIssueService is None:
        raise RuntimeError("GitHub issue dependencies are unavailable")

    return GitHubIssueService.submit_feedback_issue(
        issue_type=args.kind,
        summary=args.summary,
        details=args.details,
        user_id=args.user_id,
        user_agent=args.user_agent,
        conversation_id=args.conversation_id,
        user_message_id=args.user_message_id,
        assistant_message_id=args.assistant_message_id,
    )


def main() -> None:
    """Run CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Submit product feedback")
    parser.add_argument("--kind", required=True, choices=["bug", "feature"])
    parser.add_argument("--summary", help="Feedback summary")
    parser.add_argument("--details", help="Optional details")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--user-agent", help="User agent from request context")
    parser.add_argument("--conversation-id", help="Conversation ID")
    parser.add_argument("--user-message-id", help="User message ID")
    parser.add_argument("--assistant-message-id", help="Assistant message ID")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        result = submit_feedback(args)
        payload = {"success": True, "data": result}
        sys.stdout.write(json.dumps(payload, indent=2))
        sys.stdout.write("\n")
        sys.exit(0)
    except Exception as exc:
        error_payload = {"success": False, "error": str(exc)}
        sys.stderr.write(json.dumps(error_payload, indent=2))
        sys.stderr.write("\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
