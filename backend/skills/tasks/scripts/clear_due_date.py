#!/usr/bin/env python3
"""Clear Due Date

Remove a task's due date.
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


def clear_due_date(args: argparse.Namespace) -> dict:
    """Clear a task's due date."""
    if SessionLocal is None or TaskSyncService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        operation = {
            "op": "clear_due",
            "id": args.task_id,
        }

        TaskSyncService.apply_operations(db, args.user_id, [operation])
        db.commit()

        return {
            "taskId": args.task_id,
            "message": "Due date cleared",
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Clear a task's due date")
    parser.add_argument("task_id", help="Task ID")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = clear_due_date(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
