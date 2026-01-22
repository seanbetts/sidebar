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
        const appCandidates = ['Things3', 'Things'];
        let appName = null;
        appCandidates.forEach(name => {{
          if (appName) return;
          try {{
            const probe = Application(name);
            probe.name();
            appName = name;
          }} catch (err) {{
            // ignore
          }}
        }});
        if (!appName) {{
          throw new Error('Things app not found. Expected Things3 or Things.');
        }}
        const things = Application(appName);
        things.includeStandardAdditions = true;
        things.activate();

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

        function safeValue(fn, fallback) {{
          try {{
            return fn();
          }} catch (err) {{
            return fallback;
          }}
        }}

        function safeId(fn) {{
          const obj = safeValue(fn, null);
          return obj ? safeValue(() => obj.id(), null) : null;
        }}

        function safeString(fn) {{
          const value = safeValue(fn, null);
          if (value === null || value === undefined) return null;
          return String(value);
        }}

        const areas = (() => {{
          try {{
            return things.areas();
          }} catch (err) {{
            throw new Error('Failed to read areas: ' + err);
          }}
        }})().map(area => ({{
          id: safeString(() => area.id()),
          title: safeString(() => area.name()),
          updatedAt: isoOrNull(safeValue(() => area.modificationDate(), null))
        }})).filter(area => area.id);

        const projects = (() => {{
          try {{
            return things.projects();
          }} catch (err) {{
            throw new Error('Failed to read projects: ' + err);
          }}
        }})().map(project => ({{
          id: safeString(() => project.id()),
          title: safeString(() => project.name()),
          areaId: safeId(() => project.area()),
          status: safeString(() => project.status()),
          notes: safeString(() => project.notes()),
          updatedAt: isoOrNull(safeValue(() => project.modificationDate(), null))
        }})).filter(project => project.id);

        let tasks = [];
        const lists = (() => {{
          try {{
            return things.lists();
          }} catch (err) {{
            throw new Error('Failed to read lists: ' + err);
          }}
        }})();
        lists.forEach(list => {{
          const listName = safeString(() => list.name()) || 'Unknown';
          const todos = safeValue(() => list.toDos(), []);
          todos.forEach(todo => {{
            const taskId = safeString(() => todo.id());
            if (!taskId) return;
            tasks.push({{
              id: taskId,
              title: safeString(() => todo.name()) || 'Untitled Task',
              status: safeString(() => todo.status()) || null,
              notes: safeString(() => todo.notes()),
              dueDate: isoOrNull(safeValue(() => todo.dueDate(), null)),
              activationDate: isoOrNull(safeValue(() => todo.activationDate(), null)),
              completionDate: isoOrNull(safeValue(() => todo.completionDate(), null)),
              tags: tagNames(todo),
              projectId: safeId(() => todo.project()),
              areaId: safeId(() => todo.area()),
              updatedAt: isoOrNull(safeValue(() => todo.modificationDate(), null)),
              listName: listName
            }});
          }});
        }});

        JSON.stringify({{ areas, projects, tasks }});
    """
    try:
        result = subprocess.run(
            ["osascript", "-l", "JavaScript", "-e", script],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip() if exc.stderr else "Unknown error"
        logger.error("Things export failed: %s", stderr)
        raise RuntimeError(
            "Failed to read Things via AppleScript. Ensure Things is installed, "
            "running, and this terminal has Automation permission for Things."
        ) from exc
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
