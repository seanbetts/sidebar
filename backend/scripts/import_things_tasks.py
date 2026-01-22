#!/usr/bin/env python3
"""Import Things tasks into the native task system (one-time).

Usage:
    uv run backend/scripts/import_things_tasks.py --user-id USER_ID
    uv run backend/scripts/import_things_tasks.py --user-id USER_ID --supabase --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
from collections.abc import Iterable
from datetime import date, datetime
from pathlib import Path
from typing import Any

BACKEND_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from db_env import setup_environment  # noqa: E402

logger = logging.getLogger(__name__)


THINGS_LISTS = ("Inbox", "Today", "Anytime", "Upcoming", "Someday", "Logbook", "Trash")


def _parse_iso_date(value: str | None) -> date | None:
    if not value:
        return None
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.date()


def _map_status(list_name: str, raw_status: str | None) -> str:
    if raw_status in {"completed", "canceled"}:
        return raw_status
    if list_name == "Someday":
        return "someday"
    if list_name == "Today":
        return "today"
    if list_name == "Upcoming":
        return "upcoming"
    return "inbox"


def _run_things_export() -> dict[str, Any]:
    script = f"""
        const things = Application('Things3');
        things.includeStandardAdditions = true;

        function isoOrNull(value) {{
          if (!value) return null;
          return value.toISOString();
        }}

        function tagNames(item) {{
          try {{
            return item.tagNames();
          }} catch (err) {{
            return [];
          }}
        }}

        const areas = things.areas().map(area => ({{
          id: area.id(),
          title: area.name(),
          updatedAt: isoOrNull(area.modificationDate())
        }}));

        const projects = things.projects().map(project => ({{
          id: project.id(),
          title: project.name(),
          areaId: project.area() ? project.area().id() : null,
          status: project.status(),
          notes: project.notes(),
          updatedAt: isoOrNull(project.modificationDate())
        }}));

        const lists = {json.dumps(list(THINGS_LISTS))};
        let tasks = [];
        lists.forEach(name => {{
          const list = things.lists.byName(name);
          list.toDos().forEach(todo => {{
            tasks.push({{
              id: todo.id(),
              title: todo.name(),
              status: todo.status(),
              notes: todo.notes(),
              dueDate: isoOrNull(todo.dueDate()),
              activationDate: isoOrNull(todo.activationDate()),
              completionDate: isoOrNull(todo.completionDate()),
              tags: tagNames(todo),
              projectId: todo.project() ? todo.project().id() : null,
              areaId: todo.area() ? todo.area().id() : null,
              updatedAt: isoOrNull(todo.modificationDate()),
              listName: name
            }});
          }});
        }});

        JSON.stringify({{ areas, projects, tasks }});
    """
    result = subprocess.run(
        ["osascript", "-l", "JavaScript", "-e", script],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def _build_payload(raw: dict[str, Any]) -> dict[str, Any]:
    tasks = []
    for item in raw.get("tasks", []):
        status = _map_status(item.get("listName", ""), item.get("status"))
        tasks.append(
            {
                "id": item.get("id"),
                "title": item.get("title"),
                "status": status,
                "notes": item.get("notes"),
                "projectId": item.get("projectId"),
                "areaId": item.get("areaId"),
                "tags": item.get("tags") or [],
                "deadline": _parse_iso_date(item.get("dueDate")),
                "deadlineStart": _parse_iso_date(item.get("activationDate")),
                "updatedAt": item.get("updatedAt"),
                "repeating": False,
                "recurrenceRule": None,
            }
        )
    return {
        "areas": [
            {"id": area.get("id"), "title": area.get("title"), "updatedAt": area.get("updatedAt")}
            for area in raw.get("areas", [])
        ],
        "projects": [
            {
                "id": project.get("id"),
                "title": project.get("title"),
                "areaId": project.get("areaId"),
                "status": project.get("status"),
                "notes": project.get("notes"),
                "updatedAt": project.get("updatedAt"),
            }
            for project in raw.get("projects", [])
        ],
        "tasks": tasks,
    }


def import_things(
    user_id: str,
    *,
    dry_run: bool,
) -> None:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.tasks_import_service import TasksImportService

    raw = _run_things_export()
    payload = _build_payload(raw)
    logger.info(
        "Exported %s areas, %s projects, %s tasks from Things.",
        len(payload["areas"]),
        len(payload["projects"]),
        len(payload["tasks"]),
    )

    db = SessionLocal()
    set_session_user_id(db, user_id)
    try:
        stats = TasksImportService.import_from_payload(db, user_id, payload)
        if dry_run:
            db.rollback()
            logger.info("Dry run complete; no changes committed.")
        else:
            db.commit()
        logger.info(
            "Import complete. Areas=%s Projects=%s Tasks=%s SkippedProjects=%s SkippedTasks=%s",
            stats.areas_imported,
            stats.projects_imported,
            stats.tasks_imported,
            stats.projects_skipped,
            stats.tasks_skipped,
        )
        if stats.errors:
            logger.warning("Import errors: %s", "; ".join(stats.errors))
    finally:
        db.close()


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import Things tasks into native tables.")
    parser.add_argument("--user-id", required=True, help="User ID to import into.")
    parser.add_argument(
        "--supabase",
        action="store_true",
        help="Prompt for Supabase password and rebuild DATABASE_URL.",
    )
    parser.add_argument(
        "--database-url",
        help="Explicit DATABASE_URL to use for this run.",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Log actions without updating."
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    setup_environment(database_url=args.database_url, supabase=args.supabase)

    if str(BACKEND_ROOT) not in sys.path:
        sys.path.insert(0, str(BACKEND_ROOT))

    import_things(args.user_id, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
