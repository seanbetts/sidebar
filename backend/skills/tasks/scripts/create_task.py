#!/usr/bin/env python3
"""Create Task

Add a new task to the database.
"""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.task_sync_service import TaskSyncService
except Exception:
    SessionLocal = None
    TaskSyncService = None


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


def parse_date(value: str | None) -> date | None:
    """Parse ISO date string."""
    if not value:
        return None
    return date.fromisoformat(value)


def create_task(args: argparse.Namespace) -> dict:
    """Create a new task."""
    if SessionLocal is None or TaskSyncService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        operation = {
            "op": "add",
            "title": args.title,
        }

        if args.notes:
            operation["notes"] = args.notes
        if args.due_date:
            operation["due_date"] = args.due_date
        if args.project_id:
            operation["list_id"] = args.project_id
        elif args.group_id:
            operation["list_id"] = args.group_id

        result = TaskSyncService.apply_operations(db, args.user_id, [operation])
        db.commit()

        if result.tasks:
            task = result.tasks[0]
            return {
                "task": task_payload(task),
                "message": f"Created task: {task.title}",
            }
        else:
            raise ValueError("Task creation failed")
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a new task")
    parser.add_argument("title", help="Task title")
    parser.add_argument("--notes", help="Task notes")
    parser.add_argument("--due-date", help="Due date (ISO format: YYYY-MM-DD)")
    parser.add_argument("--project-id", help="Project ID to add task to")
    parser.add_argument("--group-id", help="Group ID to add task to")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        if not args.title.strip():
            raise ValueError("Title cannot be empty")

        result = create_task(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
