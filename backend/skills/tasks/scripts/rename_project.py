#!/usr/bin/env python3
"""Rename Project

Rename a task project title.
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


def project_payload(project) -> dict:
    """Convert project model to JSON-serializable dict."""
    return {
        "id": str(project.id),
        "title": project.title,
        "groupId": str(project.group_id) if project.group_id else None,
        "status": project.status,
    }


def rename_project(args: argparse.Namespace) -> dict:
    """Rename a project."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        project = TaskService.update_task_project(
            db, args.user_id, args.project_id, title=args.new_name
        )
        db.commit()
        return {
            "project": project_payload(project),
            "message": f"Renamed project to: {project.title}",
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Rename a task project")
    parser.add_argument("project_id", help="Project ID")
    parser.add_argument("--new-name", required=True, help="New project title")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        args.new_name = args.new_name.strip()
        if not args.new_name:
            raise ValueError("Title cannot be empty")

        result = rename_project(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
