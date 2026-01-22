"""Service for importing external task payloads into native task system."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.models.task import Task
from api.models.task_area import TaskArea
from api.models.task_project import TaskProject


@dataclass
class TasksImportStats:
    """Summary statistics for an import run."""

    areas_imported: int = 0
    projects_imported: int = 0
    projects_skipped: int = 0
    tasks_imported: int = 0
    tasks_skipped: int = 0
    errors: list[str] = field(default_factory=list)


class TasksImportService:
    """Import tasks from external payloads into native tables."""

    @staticmethod
    def import_from_bridge(
        db: Session, user_id: str, bridge_payload: dict[str, Any]
    ) -> TasksImportStats:
        """Import external data using a prepared payload.

        Args:
            db: Database session.
            user_id: Current user ID.
            bridge_payload: Parsed payload (areas, projects, tasks).

        Returns:
            TasksImportStats with counts and errors.
        """
        stats = TasksImportStats()
        now = datetime.now(UTC)

        areas_data = TasksImportService._coerce_list(bridge_payload.get("areas"))
        projects_data = TasksImportService._coerce_list(bridge_payload.get("projects"))
        tasks_data = TasksImportService._dedupe_items(
            TasksImportService._coerce_list(bridge_payload.get("tasks"))
        )

        area_map: dict[str, TaskArea] = {}
        for area_data in areas_data:
            source_id = str(area_data.get("id") or "").strip()
            if not source_id:
                continue
            existing_area = TasksImportService._find_area(db, user_id, source_id)
            title = str(area_data.get("title") or "Untitled Area")
            updated_at = TasksImportService._parse_datetime(area_data.get("updatedAt"))
            if existing_area:
                existing_area.title = title
                existing_area.updated_at = updated_at or now
                area_record = existing_area
            else:
                area_record = TaskArea(
                    user_id=user_id,
                    source_id=source_id,
                    title=title,
                    created_at=updated_at or now,
                    updated_at=updated_at or now,
                    deleted_at=None,
                )
                db.add(area_record)
                stats.areas_imported += 1
            area_map[source_id] = area_record

        project_map: dict[str, TaskProject] = {}
        for project_data in projects_data:
            status = str(project_data.get("status") or "active")
            if status in {"completed", "canceled"}:
                stats.projects_skipped += 1
                continue
            source_id = str(project_data.get("id") or "").strip()
            if not source_id:
                continue
            title = str(project_data.get("title") or "Untitled Project")
            updated_at = TasksImportService._parse_datetime(
                project_data.get("updatedAt")
            )
            area_id = project_data.get("areaId")
            project_area = area_map.get(str(area_id)) if area_id else None
            existing_project = TasksImportService._find_project(db, user_id, source_id)
            if existing_project:
                existing_project.title = title
                existing_project.status = status
                existing_project.updated_at = updated_at or now
                existing_project.area_id = project_area.id if project_area else None
                project_record = existing_project
            else:
                project_record = TaskProject(
                    user_id=user_id,
                    source_id=source_id,
                    area_id=project_area.id if project_area else None,
                    title=title,
                    status=status,
                    notes=None,
                    created_at=updated_at or now,
                    updated_at=updated_at or now,
                    completed_at=None,
                    deleted_at=None,
                )
                db.add(project_record)
                stats.projects_imported += 1
            project_map[source_id] = project_record

        for task_data in tasks_data:
            status = str(task_data.get("status") or "inbox")
            if status in {"completed", "trashed", "canceled"}:
                stats.tasks_skipped += 1
                continue
            if status in {"today", "upcoming"}:
                status = "inbox"
            source_id = str(task_data.get("id") or "").strip()
            if not source_id:
                continue
            title = str(task_data.get("title") or "Untitled Task")
            updated_at = TasksImportService._parse_datetime(task_data.get("updatedAt"))
            deadline = TasksImportService._parse_date(task_data.get("deadline"))
            deadline_start = TasksImportService._parse_date(
                task_data.get("deadlineStart")
            )
            tags = task_data.get("tags") or []
            recurrence_rule = task_data.get("recurrenceRule")
            project_id = task_data.get("projectId")
            area_id = task_data.get("areaId")
            task_project = project_map.get(str(project_id)) if project_id else None
            task_area = area_map.get(str(area_id)) if area_id else None
            existing_task = TasksImportService._find_task(db, user_id, source_id)
            if existing_task:
                existing_task.title = title
                existing_task.status = status
                existing_task.notes = task_data.get("notes")
                existing_task.deadline = deadline
                existing_task.deadline_start = deadline_start
                existing_task.project_id = task_project.id if task_project else None
                existing_task.area_id = task_area.id if task_area else None
                existing_task.tags = tags
                flag_modified(existing_task, "tags")
                existing_task.updated_at = updated_at or now
                existing_task.repeating = bool(task_data.get("repeating"))
                existing_task.recurrence_rule = recurrence_rule
                flag_modified(existing_task, "recurrence_rule")
            else:
                task = Task(
                    user_id=user_id,
                    source_id=source_id,
                    project_id=task_project.id if task_project else None,
                    area_id=task_area.id if task_area else None,
                    title=title,
                    notes=task_data.get("notes"),
                    status=status,
                    deadline=deadline,
                    deadline_start=deadline_start,
                    scheduled_date=None,
                    tags=tags,
                    repeating=bool(task_data.get("repeating")),
                    repeat_template=bool(task_data.get("repeating")),
                    repeat_template_id=None,
                    recurrence_rule=recurrence_rule,
                    next_instance_date=None,
                    created_at=updated_at or now,
                    updated_at=updated_at or now,
                    completed_at=None,
                    trashed_at=None,
                    deleted_at=None,
                )
                db.add(task)
                db.flush()
                if task.repeating and task.repeat_template_id is None:
                    task.repeat_template_id = task.id
                stats.tasks_imported += 1

        return stats

    @staticmethod
    def _coerce_list(value: Any) -> list[dict[str, Any]]:
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
        return []

    @staticmethod
    def _dedupe_items(items: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
        seen: set[str] = set()
        deduped: list[dict[str, Any]] = []
        for item in items:
            item_id = str(item.get("id") or "").strip()
            if not item_id or item_id in seen:
                continue
            seen.add(item_id)
            deduped.append(item)
        return deduped

    @staticmethod
    def _parse_datetime(value: Any) -> datetime | None:
        if not value:
            return None
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None

    @staticmethod
    def _parse_date(value: Any) -> date | None:
        parsed = TasksImportService._parse_datetime(value)
        return parsed.date() if parsed else None

    @staticmethod
    def _find_area(db: Session, user_id: str, source_id: str) -> TaskArea | None:
        return (
            db.query(TaskArea)
            .filter(
                TaskArea.user_id == user_id,
                TaskArea.source_id == source_id,
                TaskArea.deleted_at.is_(None),
            )
            .one_or_none()
        )

    @staticmethod
    def _find_project(db: Session, user_id: str, source_id: str) -> TaskProject | None:
        return (
            db.query(TaskProject)
            .filter(
                TaskProject.user_id == user_id,
                TaskProject.source_id == source_id,
                TaskProject.deleted_at.is_(None),
            )
            .one_or_none()
        )

    @staticmethod
    def _find_task(db: Session, user_id: str, source_id: str) -> Task | None:
        return (
            db.query(Task)
            .filter(
                Task.user_id == user_id,
                Task.source_id == source_id,
                Task.deleted_at.is_(None),
            )
            .one_or_none()
        )
