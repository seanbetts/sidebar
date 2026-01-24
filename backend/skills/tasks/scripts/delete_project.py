#!/usr/bin/env python3
"""Delete Project

Soft-delete a task project.
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


def delete_project(args: argparse.Namespace) -> dict:
    """Delete a project."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        project = TaskService.delete_task_project(db, args.user_id, args.project_id)
        db.commit()

        return {
            "projectId": str(project.id),
            "title": project.title,
            "message": f"Project '{project.title}' deleted",
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete a project")
    parser.add_argument("project_id", help="Project ID to delete")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        result = delete_project(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
