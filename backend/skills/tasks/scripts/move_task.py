#!/usr/bin/env python3
"""Move Task

Move a task to a different project or group.
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


def move_task(args: argparse.Namespace) -> dict:
    """Move a task to a different project or group."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        # Get the task first to include in response
        task = TaskService.get_task(db, args.user_id, args.task_id)
        old_project_id = str(task.project_id) if task.project_id else None
        old_group_id = str(task.group_id) if task.group_id else None

        # Update the task location
        task = TaskService.update_task(
            db,
            args.user_id,
            args.task_id,
            project_id=args.project_id,
            group_id=args.group_id if not args.project_id else None,
        )
        db.commit()

        result = {
            "taskId": str(task.id),
            "title": task.title,
        }

        if args.project_id:
            result["projectId"] = args.project_id
            result["message"] = f"Task '{task.title}' moved to project"
        elif args.group_id:
            result["groupId"] = args.group_id
            result["message"] = f"Task '{task.title}' moved to group"
        else:
            result["message"] = f"Task '{task.title}' moved to inbox"

        if old_project_id:
            result["previousProjectId"] = old_project_id
        if old_group_id:
            result["previousGroupId"] = old_group_id

        return result
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Move a task")
    parser.add_argument("task_id", help="Task ID to move")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--project-id", help="Target project ID")
    parser.add_argument("--group-id", help="Target group ID (if not using project)")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = move_task(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
