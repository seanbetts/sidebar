#!/usr/bin/env python3
"""Rename Task

Rename a task title.
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


def rename_task(args: argparse.Namespace) -> dict:
    """Rename a task."""
    if SessionLocal is None or TaskSyncService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        operation = {
            "op": "rename",
            "id": args.task_id,
            "title": args.new_name,
        }
        result = TaskSyncService.apply_operations(db, args.user_id, [operation])
        db.commit()

        if result.tasks:
            task = result.tasks[0]
            return {
                "task": task_payload(task),
                "message": f"Renamed task to: {task.title}",
            }

        return {
            "taskId": args.task_id,
            "title": args.new_name,
            "message": f"Renamed task to: {args.new_name}",
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Rename a task")
    parser.add_argument("task_id", help="Task ID")
    parser.add_argument("--new-name", required=True, help="New task title")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        args.new_name = args.new_name.strip()
        if not args.new_name:
            raise ValueError("Title cannot be empty")

        result = rename_task(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
