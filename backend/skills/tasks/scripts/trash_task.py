#!/usr/bin/env python3
"""Trash Task

Soft-delete a task and its repeat series.
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


def trash_task(args: argparse.Namespace) -> dict:
    """Trash a task."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        trashed = TaskService.trash_task_series(db, args.user_id, args.task_id)
        db.commit()

        count = len(trashed)
        if count == 0:
            return {
                "taskId": args.task_id,
                "message": "Task not found",
            }
        elif count == 1:
            return {
                "taskId": args.task_id,
                "message": "Task deleted",
            }
        else:
            return {
                "taskId": args.task_id,
                "trashedCount": count,
                "message": f"Task and {count - 1} repeat instances deleted",
            }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Trash a task")
    parser.add_argument("task_id", help="Task ID to trash")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = trash_task(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
