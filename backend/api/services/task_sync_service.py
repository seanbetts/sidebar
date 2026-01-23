"""Service layer for task sync and offline operations."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError
from api.models.task import Task
from api.models.task_area import TaskArea
from api.models.task_operation_log import TaskOperationLog
from api.models.task_project import TaskProject
from api.services.recurrence_service import RecurrenceService
from api.services.task_service import TaskService
from api.utils.validation import parse_optional_uuid


@dataclass
class ApplyResult:
    """Result summary for applied operations."""

    applied_ids: list[str]
    tasks: list[Task]
    next_tasks: list[Task]


@dataclass
class ApplyOutcome:
    """Internal result summary for applied operations with conflict tracking."""

    applied_ids: list[str]
    tasks: list[Task]
    next_tasks: list[Task]
    conflicts: list[dict[str, Any]]


@dataclass
class SyncResult:
    """Result summary for sync operations and delta updates."""

    applied_ids: list[str]
    tasks: list[Task]
    next_tasks: list[Task]
    conflicts: list[dict[str, Any]]
    updated_tasks: list[Task]
    updated_projects: list[TaskProject]
    updated_areas: list[TaskArea]
    server_updated_since: datetime


class TaskSyncService:
    """Service for offline sync and batched task operations."""

    @staticmethod
    def apply_operations(
        db: Session, user_id: str, operations: list[dict[str, Any]]
    ) -> ApplyResult:
        """Apply task operations and log for idempotency."""
        outcome = TaskSyncService._apply_operations(
            db, user_id, operations, check_conflicts=False
        )
        return ApplyResult(
            applied_ids=outcome.applied_ids,
            tasks=outcome.tasks,
            next_tasks=outcome.next_tasks,
        )

    @staticmethod
    def sync_operations(
        db: Session, user_id: str, payload: dict[str, Any]
    ) -> SyncResult:
        """Apply operations and return delta updates for offline sync."""
        last_sync = TaskSyncService._parse_datetime(
            payload.get("last_sync"), field_name="last_sync"
        )
        operations = payload.get("operations") or []
        if operations and not isinstance(operations, list):
            raise BadRequestError("operations must be a list")

        outcome = TaskSyncService._apply_operations(
            db, user_id, operations, check_conflicts=True
        )
        updated_tasks, updated_projects, updated_areas = (
            TaskSyncService.list_updates_since(db, user_id, last_sync)
        )
        server_updated_since = TaskSyncService._max_updated_at(
            updated_tasks,
            updated_projects,
            updated_areas,
            outcome.tasks,
            outcome.next_tasks,
        )
        return SyncResult(
            applied_ids=outcome.applied_ids,
            tasks=outcome.tasks,
            next_tasks=outcome.next_tasks,
            conflicts=outcome.conflicts,
            updated_tasks=updated_tasks,
            updated_projects=updated_projects,
            updated_areas=updated_areas,
            server_updated_since=server_updated_since,
        )

    @staticmethod
    def list_updates_since(
        db: Session, user_id: str, last_sync: datetime | None
    ) -> tuple[list[Task], list[TaskProject], list[TaskArea]]:
        """List task data updated since the provided timestamp."""
        tasks_query = db.query(Task).filter(Task.user_id == user_id)
        projects_query = db.query(TaskProject).filter(TaskProject.user_id == user_id)
        areas_query = db.query(TaskArea).filter(TaskArea.user_id == user_id)

        if last_sync is None:
            tasks_query = tasks_query.filter(Task.deleted_at.is_(None))
            projects_query = projects_query.filter(TaskProject.deleted_at.is_(None))
            areas_query = areas_query.filter(TaskArea.deleted_at.is_(None))
        else:
            tasks_query = tasks_query.filter(Task.updated_at >= last_sync)
            projects_query = projects_query.filter(TaskProject.updated_at >= last_sync)
            areas_query = areas_query.filter(TaskArea.updated_at >= last_sync)

        tasks = tasks_query.order_by(Task.updated_at.asc()).all()
        projects = projects_query.order_by(TaskProject.updated_at.asc()).all()
        areas = areas_query.order_by(TaskArea.updated_at.asc()).all()
        return tasks, projects, areas

    @staticmethod
    def _apply_operations(
        db: Session,
        user_id: str,
        operations: list[dict[str, Any]],
        *,
        check_conflicts: bool,
    ) -> ApplyOutcome:
        """Apply task operations with optional conflict checks."""
        applied_ids: list[str] = []
        tasks: list[Task] = []
        next_tasks: list[Task] = []
        conflicts: list[dict[str, Any]] = []

        for operation in operations:
            operation_id = str(operation.get("operation_id") or "").strip()
            if not operation_id:
                operation_id = str(uuid.uuid4())
            existing_log = (
                db.query(TaskOperationLog)
                .filter(
                    TaskOperationLog.user_id == user_id,
                    TaskOperationLog.operation_id == operation_id,
                )
                .one_or_none()
            )
            if existing_log:
                applied_ids.append(operation_id)
                if check_conflicts:
                    conflict_payload = TaskSyncService._extract_conflict(existing_log)
                    if conflict_payload:
                        conflicts.append(conflict_payload)
                continue

            op = operation.get("op")
            if check_conflicts and op in {
                "complete",
                "rename",
                "notes",
                "move",
                "trash",
                "set_due",
                "defer",
                "clear_due",
                "set_repeat",
            }:
                client_updated_at = TaskSyncService._parse_datetime(
                    operation.get("client_updated_at"), field_name="client_updated_at"
                )
                task = TaskService.get_task(db, user_id, operation["id"])
                if TaskSyncService._has_conflict(task, client_updated_at):
                    conflict_payload = TaskSyncService._build_task_conflict(
                        task, operation_id, op, client_updated_at
                    )
                    conflicts.append(conflict_payload)
                    TaskSyncService._log_operation(
                        db,
                        user_id,
                        operation_id,
                        op,
                        operation,
                        conflict_payload,
                    )
                    applied_ids.append(operation_id)
                    continue

            if op == "add":
                task = TaskSyncService._apply_add(db, user_id, operation)
                tasks.append(task)
            elif op == "complete":
                task, next_task = TaskService.complete_task(
                    db, user_id, operation["id"]
                )
                tasks.append(task)
                if next_task:
                    next_tasks.append(next_task)
            elif op == "rename":
                task = TaskService.update_task(
                    db, user_id, operation["id"], title=operation["title"]
                )
                tasks.append(task)
            elif op == "notes":
                task = TaskService.update_task(
                    db, user_id, operation["id"], notes=operation.get("notes")
                )
                tasks.append(task)
            elif op == "move":
                task = TaskSyncService._apply_move(db, user_id, operation)
                tasks.append(task)
            elif op == "trash":
                task = TaskService.update_task(
                    db, user_id, operation["id"], status="trashed"
                )
                now = datetime.now(UTC)
                task.trashed_at = now
                task.deleted_at = now
                tasks.append(task)
            elif op in {"set_due", "defer"}:
                task = TaskSyncService._apply_due_date(db, user_id, operation)
                tasks.append(task)
            elif op == "clear_due":
                task = TaskSyncService._apply_clear_due(db, user_id, operation)
                tasks.append(task)
            elif op == "set_repeat":
                updated = TaskSyncService._apply_repeat(db, user_id, operation)
                tasks.extend(updated)
            else:
                continue

            TaskSyncService._log_operation(db, user_id, operation_id, op, operation)
            applied_ids.append(operation_id)

        return ApplyOutcome(
            applied_ids=applied_ids,
            tasks=tasks,
            next_tasks=next_tasks,
            conflicts=conflicts,
        )

    @staticmethod
    def _parse_datetime(value: Any, *, field_name: str) -> datetime | None:
        if not value:
            return None
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError as exc:
            raise BadRequestError(f"Invalid {field_name} timestamp") from exc
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=UTC)
        return parsed

    @staticmethod
    def _has_conflict(task: Task, client_updated_at: datetime | None) -> bool:
        if not client_updated_at or not task.updated_at:
            return False
        return task.updated_at > client_updated_at

    @staticmethod
    def _build_task_conflict(
        task: Task,
        operation_id: str,
        op: str | None,
        client_updated_at: datetime | None,
    ) -> dict[str, Any]:
        return {
            "operationId": operation_id,
            "op": op,
            "id": str(task.id),
            "clientUpdatedAt": client_updated_at.isoformat()
            if client_updated_at
            else None,
            "serverUpdatedAt": task.updated_at.isoformat() if task.updated_at else None,
            "serverTask": TaskSyncService._task_sync_payload(task),
        }

    @staticmethod
    def _extract_conflict(log: TaskOperationLog) -> dict[str, Any] | None:
        payload = log.payload or {}
        if isinstance(payload, dict) and payload.get("_conflict_payload"):
            return payload.get("_conflict_payload")
        return None

    @staticmethod
    def _log_operation(
        db: Session,
        user_id: str,
        operation_id: str,
        operation_type: str | None,
        operation: dict[str, Any],
        conflict_payload: dict[str, Any] | None = None,
    ) -> None:
        payload = dict(operation)
        if conflict_payload is not None:
            payload["_conflict_payload"] = conflict_payload
        log = TaskOperationLog(
            user_id=user_id,
            operation_id=operation_id,
            operation_type=str(operation_type),
            payload=payload,
            created_at=datetime.now(UTC),
        )
        db.add(log)

    @staticmethod
    def _task_sync_payload(task: Task) -> dict[str, Any]:
        deadline = task.deadline or task.scheduled_date
        next_instance = RecurrenceService.next_instance_date(task)
        return {
            "id": str(task.id),
            "title": task.title,
            "status": task.status,
            "deadline": deadline.isoformat() if deadline else None,
            "notes": task.notes,
            "projectId": str(task.project_id) if task.project_id else None,
            "areaId": str(task.area_id) if task.area_id else None,
            "repeating": task.repeating,
            "repeatTemplate": task.repeat_template,
            "recurrenceRule": task.recurrence_rule,
            "nextInstanceDate": next_instance.isoformat() if next_instance else None,
            "updatedAt": task.updated_at.isoformat() if task.updated_at else None,
            "deletedAt": task.deleted_at.isoformat() if task.deleted_at else None,
        }

    @staticmethod
    def _max_updated_at(*collections: list[Any]) -> datetime:
        latest: datetime | None = None
        for collection in collections:
            for item in collection:
                updated_at = getattr(item, "updated_at", None)
                if updated_at and (latest is None or updated_at > latest):
                    latest = updated_at
        return latest or datetime.now(UTC)

    @staticmethod
    def _apply_add(db: Session, user_id: str, operation: dict[str, Any]) -> Task:
        list_id = operation.get("list_id")
        project = (
            db.query(TaskProject)
            .filter(
                TaskProject.id == parse_optional_uuid(list_id, "task project", "id"),
                TaskProject.user_id == user_id,
                TaskProject.deleted_at.is_(None),
            )
            .one_or_none()
            if list_id
            else None
        )
        area = (
            db.query(TaskArea)
            .filter(
                TaskArea.id == parse_optional_uuid(list_id, "task area", "id"),
                TaskArea.user_id == user_id,
                TaskArea.deleted_at.is_(None),
            )
            .one_or_none()
            if list_id and not project
            else None
        )
        due_date = TaskSyncService._parse_date(operation.get("due_date"))
        return TaskService.create_task(
            db,
            user_id,
            title=operation.get("title") or "Untitled Task",
            notes=operation.get("notes"),
            deadline=due_date,
            project_id=str(project.id) if project else None,
            area_id=str(area.id) if area else None,
        )

    @staticmethod
    def _apply_move(db: Session, user_id: str, operation: dict[str, Any]) -> Task:
        list_id = operation.get("list_id")
        project = (
            db.query(TaskProject)
            .filter(
                TaskProject.id == parse_optional_uuid(list_id, "task project", "id"),
                TaskProject.user_id == user_id,
                TaskProject.deleted_at.is_(None),
            )
            .one_or_none()
            if list_id
            else None
        )
        area = (
            db.query(TaskArea)
            .filter(
                TaskArea.id == parse_optional_uuid(list_id, "task area", "id"),
                TaskArea.user_id == user_id,
                TaskArea.deleted_at.is_(None),
            )
            .one_or_none()
            if list_id and not project
            else None
        )
        return TaskService.update_task(
            db,
            user_id,
            operation["id"],
            project_id=str(project.id) if project else None,
            area_id=str(area.id) if area else None,
        )

    @staticmethod
    def _apply_due_date(db: Session, user_id: str, operation: dict[str, Any]) -> Task:
        due_date = TaskSyncService._parse_date(operation.get("due_date"))
        task = TaskService.get_task(db, user_id, operation["id"])
        scheduled_date = due_date if task.scheduled_date is not None else None
        return TaskService.update_task(
            db,
            user_id,
            operation["id"],
            deadline=due_date,
            scheduled_date=scheduled_date,
        )

    @staticmethod
    def _apply_repeat(
        db: Session, user_id: str, operation: dict[str, Any]
    ) -> list[Task]:
        rule = operation.get("recurrence_rule")
        if rule is not None and not isinstance(rule, dict):
            raise BadRequestError("Invalid recurrence rule")
        anchor_date = TaskSyncService._parse_date(operation.get("start_date"))
        return TaskService.set_task_recurrence(
            db,
            user_id,
            operation["id"],
            recurrence_rule=rule,
            anchor_date=anchor_date,
        )

    @staticmethod
    def _apply_clear_due(db: Session, user_id: str, operation: dict[str, Any]) -> Task:
        return TaskService.clear_task_due(db, user_id, operation["id"])

    @staticmethod
    def _parse_date(value: Any) -> date | None:
        if not value:
            return None
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00")).date()
        except ValueError:
            return None
