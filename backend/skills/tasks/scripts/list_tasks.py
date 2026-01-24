#!/usr/bin/env python3
"""List Tasks

Fetch tasks by scope (today, upcoming, inbox) from the database.
"""

import argparse
import json
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(BACKEND_ROOT))

try:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.recurrence_service import RecurrenceService
    from api.services.task_service import TaskService
except Exception:
    SessionLocal = None
    TaskService = None
    RecurrenceService = None


def task_payload(task) -> dict:
    """Convert task model to JSON-serializable dict."""
    deadline = task.deadline
    next_instance = RecurrenceService.next_instance_date(task)
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


def project_payload(project) -> dict:
    """Convert project model to JSON-serializable dict."""
    return {
        "id": str(project.id),
        "title": project.title,
        "groupId": str(project.group_id) if project.group_id else None,
    }


def group_payload(group) -> dict:
    """Convert group model to JSON-serializable dict."""
    return {
        "id": str(group.id),
        "title": group.title,
    }


def list_tasks(args: argparse.Namespace) -> dict:
    """List tasks by scope."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        tasks, projects, groups = TaskService.list_tasks_by_scope(
            db, args.user_id, args.scope
        )
        return {
            "scope": args.scope,
            "tasks": [task_payload(task) for task in tasks],
            "projects": [project_payload(project) for project in projects],
            "groups": [group_payload(group) for group in groups],
            "count": len(tasks),
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="List tasks by scope")
    parser.add_argument(
        "scope",
        choices=["today", "upcoming", "inbox"],
        help="Task scope to fetch",
    )
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = list_tasks(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
