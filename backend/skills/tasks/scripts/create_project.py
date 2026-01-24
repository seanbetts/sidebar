#!/usr/bin/env python3
"""Create Project

Create a new task project.
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


def create_project(args: argparse.Namespace) -> dict:
    """Create a new project."""
    if SessionLocal is None or TaskService is None:
        raise RuntimeError("Database dependencies are unavailable")

    db = SessionLocal()
    set_session_user_id(db, args.user_id)

    try:
        project = TaskService.create_task_project(
            db, args.user_id, args.title, group_id=args.group_id
        )
        db.commit()

        return {
            "project": project_payload(project),
            "message": f"Created project: {project.title}",
        }
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a new project")
    parser.add_argument("title", help="Project title")
    parser.add_argument("--group-id", help="Group ID to add project to")
    parser.add_argument("--user-id", required=True, help="User ID")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    try:
        if not args.title.strip():
            raise ValueError("Title cannot be empty")

        result = create_project(args)
        output = {"success": True, "data": result}
        print(json.dumps(output, indent=2))
        sys.exit(0)

    except Exception as e:
        error_output = {"success": False, "error": str(e)}
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
