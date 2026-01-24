#!/usr/bin/env python3
"""Complete Task

Mark a task as completed. For repeating tasks, creates the next instance.
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


def complete_task(args: argparse.Namespace) -> dict:
    """Complete a task."""
    if SessionLocal is None or TaskSyncService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        operation = {
            "op": "complete",
            "id": args.task_id,
        }

        result = TaskSyncService.apply_operations(db, args.user_id, [operation])
        db.commit()

        response = {
            "taskId": args.task_id,
            "message": "Task completed",
        }

        if result.next_tasks:
            next_task = result.next_tasks[0]
            response["nextTask"] = task_payload(next_task)
            response["message"] = f"Task completed. Next instance created for {next_task.deadline}"

        return response
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Complete a task")
    parser.add_argument("task_id", help="Task ID to complete")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = complete_task(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
