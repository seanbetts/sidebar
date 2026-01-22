#!/usr/bin/env python3
"""Import Things tasks from a local SQLite database (one-time).

Usage:
    uv run backend/scripts/import_things_sqlite.py --user-id USER_ID
    uv run backend/scripts/import_things_sqlite.py --user-id USER_ID --dry-run
"""

from __future__ import annotations

import argparse
import logging
import sqlite3
import sys
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime, timezone, timedelta
from pathlib import Path
from typing import Any

BACKEND_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_ROOT = Path(__file__).resolve().parent
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from db_env import setup_environment  # noqa: E402

logger = logging.getLogger(__name__)


REFERENCE_START_VALUE = 132782464
REFERENCE_START_DATE = date(2026, 1, 19)


@dataclass(frozen=True)
class StartDateConverter:
    """Convert Things start/deadline integers into dates."""

    base_datetime: datetime

    def to_date(self, value: int | None) -> date | None:
        if value is None:
            return None
        return (self.base_datetime + timedelta(seconds=int(value))).date()


def parse_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    value = value.strip().lower()
    if value in {"true", "1", "yes", "y"}:
        return True
    if value in {"false", "0", "no", "n"}:
        return False
    raise ValueError(f"Invalid boolean value: {value}")


def iso_from_timestamp(value: float | int | None) -> str | None:
    if value is None:
        return None
    return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat()


def build_start_converter(
    reference_value: int, reference_date: date
) -> StartDateConverter:
    base = datetime.combine(reference_date, datetime.min.time(), tzinfo=timezone.utc)
    base -= timedelta(seconds=reference_value)
    return StartDateConverter(base_datetime=base)


def load_tags(conn: sqlite3.Connection) -> dict[str, str]:
    tags: dict[str, str] = {}
    try:
        rows = conn.execute("select uuid, title from TMTag").fetchall()
    except sqlite3.OperationalError:
        return tags
    for uuid, title in rows:
        if not uuid or not title:
            continue
        tags[str(uuid)] = str(title)
    return tags


def load_task_tags(conn: sqlite3.Connection, tag_map: dict[str, str]) -> dict[str, list[str]]:
    task_tags: dict[str, list[str]] = defaultdict(list)
    try:
        rows = conn.execute("select tasks, tags from TMTaskTag").fetchall()
    except sqlite3.OperationalError:
        return task_tags
    for task_id, tag_id in rows:
        if not task_id or not tag_id:
            continue
        tag_name = tag_map.get(str(tag_id))
        if not tag_name:
            continue
        task_tags[str(task_id)].append(tag_name)
    return task_tags


def map_task_status(
    *,
    status: int | None,
    trashed: int | None,
    stop_date: float | None,
    start_date: date | None,
    today: date,
) -> str:
    if trashed:
        return "trashed"
    if status == 3 or stop_date:
        return "completed"
    if start_date:
        return "upcoming" if start_date > today else "today"
    return "inbox"


def fetch_areas(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    areas: list[dict[str, Any]] = []
    try:
        rows = conn.execute(
            "select uuid, title, visible from TMArea"
        ).fetchall()
    except sqlite3.OperationalError:
        return areas
    for uuid, title, visible in rows:
        if not uuid or not title:
            continue
        if visible is not None and int(visible) == 0:
            continue
        areas.append({"id": str(uuid), "title": str(title), "updatedAt": None})
    return areas


def fetch_projects(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    projects: list[dict[str, Any]] = []
    try:
        rows = conn.execute(
            """
            select uuid, title, area, status, notes, userModificationDate, trashed
            from TMTask
            where type = 1
            """
        ).fetchall()
    except sqlite3.OperationalError:
        return projects
    for uuid, title, area_id, status, notes, updated_at, trashed in rows:
        if not uuid or not title:
            continue
        if trashed:
            continue
        project_status = "completed" if status == 3 else "active"
        projects.append(
            {
                "id": str(uuid),
                "title": str(title),
                "areaId": str(area_id) if area_id else None,
                "status": project_status,
                "notes": str(notes) if notes else None,
                "updatedAt": iso_from_timestamp(updated_at),
            }
        )
    return projects


def fetch_tasks(
    conn: sqlite3.Connection,
    *,
    converter: StartDateConverter,
    task_tags: dict[str, list[str]],
    include_completed: bool,
    include_trashed: bool,
) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    today = date.today()

    try:
        rows = conn.execute(
            """
            select uuid, title, notes, status, trashed, stopDate, project, area,
                   startDate, deadline, userModificationDate, rt1_recurrenceRule
            from TMTask
            where type = 0
            """
        ).fetchall()
    except sqlite3.OperationalError:
        return tasks
    for row in rows:
        (
            uuid,
            title,
            notes,
            status,
            trashed,
            stop_date,
            project_id,
            area_id,
            start_date_value,
            deadline_value,
            updated_at,
            recurrence_blob,
        ) = row
        if not uuid or not title:
            continue
        start_date = converter.to_date(start_date_value)
        status_value = map_task_status(
            status=status,
            trashed=trashed,
            stop_date=stop_date,
            start_date=start_date,
            today=today,
        )
        if status_value == "completed" and not include_completed:
            continue
        if status_value == "trashed" and not include_trashed:
            continue

        tasks.append(
            {
                "id": str(uuid),
                "title": str(title),
                "status": status_value,
                "notes": str(notes) if notes else None,
                "projectId": str(project_id) if project_id else None,
                "areaId": str(area_id) if area_id else None,
                "tags": task_tags.get(str(uuid), []),
                "deadline": converter.to_date(deadline_value),
                "deadlineStart": start_date,
                "updatedAt": iso_from_timestamp(updated_at),
                "repeating": recurrence_blob is not None,
                "recurrenceRule": recurrence_blob,
            }
        )
    return tasks


def import_things_sqlite(
    *,
    user_id: str,
    db_path: Path,
    dry_run: bool,
    include_completed: bool,
    include_trashed: bool,
    reference_value: int,
    reference_date: date,
) -> None:
    from api.db.session import SessionLocal, set_session_user_id
    from api.services.recurrence_plist_parser import RecurrencePlistParser
    from api.services.tasks_import_service import TasksImportService

    converter = build_start_converter(reference_value, reference_date)
    conn = sqlite3.connect(str(db_path))
    try:
        tag_map = load_tags(conn)
        task_tags = load_task_tags(conn, tag_map)
        areas = fetch_areas(conn)
        projects = fetch_projects(conn)
        tasks = fetch_tasks(
            conn,
            converter=converter,
            task_tags=task_tags,
            include_completed=include_completed,
            include_trashed=include_trashed,
        )
    finally:
        conn.close()

    for task in tasks:
        recurrence_blob = task.get("recurrenceRule")
        task["recurrenceRule"] = RecurrencePlistParser.parse_recurrence_rule(
            recurrence_blob
        )
        task["repeating"] = bool(task["recurrenceRule"])

    payload = {"areas": areas, "projects": projects, "tasks": tasks}
    logger.info(
        "Loaded Things data: %s areas, %s projects, %s tasks",
        len(areas),
        len(projects),
        len(tasks),
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
    finally:
        db.close()


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import Things SQLite data.")
    parser.add_argument("--user-id", required=True, help="User ID to import into.")
    parser.add_argument(
        "--database-path",
        default="main.sqlite",
        help="Path to Things SQLite database (default: main.sqlite).",
    )
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
    parser.add_argument(
        "--include-completed",
        action="store_true",
        help="Include completed tasks (default: skip).",
    )
    parser.add_argument(
        "--include-trashed",
        action="store_true",
        help="Include trashed tasks (default: skip).",
    )
    parser.add_argument(
        "--reference-start-value",
        type=int,
        default=REFERENCE_START_VALUE,
        help="Reference startDate integer for date conversion.",
    )
    parser.add_argument(
        "--reference-start-date",
        default=REFERENCE_START_DATE.isoformat(),
        help="Reference date (YYYY-MM-DD) for date conversion.",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> None:
    args = parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    setup_environment(database_url=args.database_url, supabase=args.supabase)

    if str(BACKEND_ROOT) not in sys.path:
        sys.path.insert(0, str(BACKEND_ROOT))

    import_things_sqlite(
        user_id=args.user_id,
        db_path=Path(args.database_path),
        dry_run=args.dry_run,
        include_completed=args.include_completed,
        include_trashed=args.include_trashed,
        reference_value=args.reference_start_value,
        reference_date=date.fromisoformat(args.reference_start_date),
    )


if __name__ == "__main__":
    main()
