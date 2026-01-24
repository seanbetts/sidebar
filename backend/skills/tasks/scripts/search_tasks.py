#!/usr/bin/env python3
"""Search Tasks

Search tasks by title or notes content.
"""

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.task_service import TaskService
except Exception:
    SessionLocal = None
    TaskService = None


def task_payload(task) -> dict:
    """Convert task model to JSON-serializable dict."""
    deadline = task.deadline
    return {
        "id": str(task.id),
        "title": task.title,
        "status": task.status,
        "deadline": deadline.isoformat() if deadline else None,
        "notes": task.notes,
        "projectId": str(task.project_id) if task.project_id else None,
        "groupId": str(task.group_id) if task.group_id else None,
        "repeating": task.repeating,
    }


def search_tasks(args: argparse.Namespace) -> dict:
    """Search tasks by query."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        tasks = TaskService.search_tasks(db, args.user_id, args.query)
        return {
            "query": args.query,
            "tasks": [task_payload(task) for task in tasks],
            "count": len(tasks),
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Search tasks")
    parser.add_argument("query", help="Search query")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        if not args.query.strip():
            raise ValueError("Query cannot be empty")

        result = search_tasks(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
