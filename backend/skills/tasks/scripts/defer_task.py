#!/usr/bin/env python3
"""Defer Task

Change a task's due date.
"""

import argparse
import json
import sys
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


def defer_task(args: argparse.Namespace) -> dict:
    """Defer a task to a new date."""
    if SessionLocal is None or TaskSyncService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        operation = {
            "op": "defer",
            "id": args.task_id,
            "due_date": args.due_date,
        }

        result = TaskSyncService.apply_operations(db, args.user_id, [operation])
        db.commit()

        if result.tasks:
            task = result.tasks[0]
            return {
                "task": task_payload(task),
                "message": f"Task deferred to {args.due_date}",
            }
        else:
            return {
                "taskId": args.task_id,
                "dueDate": args.due_date,
                "message": f"Task deferred to {args.due_date}",
            }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Defer a task")
    parser.add_argument("task_id", help="Task ID to defer")
    parser.add_argument("due_date", help="New due date (ISO format: YYYY-MM-DD)")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = defer_task(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
