#!/usr/bin/env python3
"""Set Task Repeat

Set or clear a task recurrence rule.
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
    from api.services.task_service import TaskService
    from api.services.task_sync_service import TaskSyncService
except Exception:
    SessionLocal = None
    TaskService = None
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
        "recurrenceRule": task.recurrence_rule,
    }


def parse_recurrence_rule(value: str) -> dict | None:
    """Parse a recurrence rule from JSON."""
    parsed = json.loads(value)
    if parsed is None:
        return None
    if not isinstance(parsed, dict):
        raise ValueError("recurrence_rule must be an object or null")

    rule_type = parsed.get("type")
    if rule_type not in {"daily", "weekly", "monthly"}:
        raise ValueError("recurrence_rule.type must be daily, weekly, or monthly")

    if parsed.get("interval") is not None and int(parsed["interval"]) < 1:
        raise ValueError("recurrence_rule.interval must be >= 1")

    return parsed


def set_task_repeat(args: argparse.Namespace) -> dict:
    """Set task recurrence rule."""
    if SessionLocal is None or TaskSyncService is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        recurrence_rule = parse_recurrence_rule(args.recurrence_rule)
        start_date = args.start_date
        if recurrence_rule is not None and not start_date:
            task = TaskService.get_task(db, args.user_id, args.task_id)
            if task.deadline:
                start_date = task.deadline.isoformat()

        operation = {
            "op": "set_repeat",
            "id": args.task_id,
            "recurrence_rule": recurrence_rule,
        }
        if start_date:
            operation["start_date"] = start_date

        result = TaskSyncService.apply_operations(db, args.user_id, [operation])
        db.commit()

        if result.tasks:
            task = next(
                (item for item in result.tasks if str(item.id) == args.task_id),
                result.tasks[0],
            )
            return {
                "task": task_payload(task),
                "updatedCount": len(result.tasks),
                "message": (
                    "Task repeat cleared"
                    if recurrence_rule is None
                    else "Task repeat updated"
                ),
            }

        return {
            "taskId": args.task_id,
            "recurrenceRule": recurrence_rule,
            "startDate": start_date,
            "message": "Task repeat cleared"
            if recurrence_rule is None
            else "Task repeat updated",
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Set or clear task repeat")
    parser.add_argument("task_id", help="Task ID")
    parser.add_argument(
        "--recurrence-rule",
        required=True,
        help="Recurrence rule JSON object, or null to clear",
    )
    parser.add_argument("--start-date", help="Anchor date (ISO format: YYYY-MM-DD)")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        if args.start_date:
            date.fromisoformat(args.start_date)

        result = set_task_repeat(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
