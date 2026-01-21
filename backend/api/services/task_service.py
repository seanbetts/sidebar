"""Service layer for native task system."""

from __future__ import annotations

from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.exceptions import (
    TaskAreaNotFoundError,
    TaskNotFoundError,
    TaskProjectNotFoundError,
)
from api.models.task import Task
from api.models.task_area import TaskArea
from api.models.task_project import TaskProject
from api.services.recurrence_service import RecurrenceService
from api.utils.validation import parse_optional_uuid, parse_uuid


class TaskService:
    """Service layer for task CRUD operations."""

    @staticmethod
    def create_task_area(
        db: Session,
        user_id: str,
        title: str,
        *,
        things_id: str | None = None,
    ) -> TaskArea:
        """Create a new task area.

        Args:
            db: Database session.
            user_id: Current user ID.
            title: Area title.
            things_id: Optional Things identifier.

        Returns:
            Newly created TaskArea.
        """
        now = datetime.now(UTC)
        area = TaskArea(
            user_id=user_id,
            title=title,
            things_id=things_id,
            created_at=now,
            updated_at=now,
            deleted_at=None,
        )
        db.add(area)
        db.flush()
        return area

    @staticmethod
    def get_task_area(db: Session, user_id: str, area_id: str) -> TaskArea:
        """Fetch a task area by ID.

        Args:
            db: Database session.
            user_id: Current user ID.
            area_id: Task area ID.

        Returns:
            TaskArea record.

        Raises:
            TaskAreaNotFoundError: If no matching area is found.
        """
        parsed_id = parse_uuid(area_id, "task area", "id")
        area = (
            db.query(TaskArea)
            .filter(
                TaskArea.id == parsed_id,
                TaskArea.user_id == user_id,
                TaskArea.deleted_at.is_(None),
            )
            .one_or_none()
        )
        if not area:
            raise TaskAreaNotFoundError(area_id)
        return area

    @staticmethod
    def list_task_areas(db: Session, user_id: str) -> list[TaskArea]:
        """List active task areas for a user."""
        return (
            db.query(TaskArea)
            .filter(TaskArea.user_id == user_id, TaskArea.deleted_at.is_(None))
            .order_by(TaskArea.title.asc())
            .all()
        )

    @staticmethod
    def update_task_area(
        db: Session,
        user_id: str,
        area_id: str,
        *,
        title: str,
    ) -> TaskArea:
        """Update task area metadata."""
        area = TaskService.get_task_area(db, user_id, area_id)
        area.title = title
        area.updated_at = datetime.now(UTC)
        return area

    @staticmethod
    def delete_task_area(db: Session, user_id: str, area_id: str) -> TaskArea:
        """Soft-delete a task area."""
        area = TaskService.get_task_area(db, user_id, area_id)
        now = datetime.now(UTC)
        area.deleted_at = now
        area.updated_at = now
        return area

    @staticmethod
    def create_task_project(
        db: Session,
        user_id: str,
        title: str,
        *,
        area_id: str | None = None,
        status: str = "active",
        notes: str | None = None,
        things_id: str | None = None,
    ) -> TaskProject:
        """Create a new task project."""
        now = datetime.now(UTC)
        project = TaskProject(
            user_id=user_id,
            title=title,
            area_id=parse_optional_uuid(area_id, "task area", "id"),
            status=status,
            notes=notes,
            things_id=things_id,
            created_at=now,
            updated_at=now,
            deleted_at=None,
        )
        db.add(project)
        db.flush()
        return project

    @staticmethod
    def get_task_project(db: Session, user_id: str, project_id: str) -> TaskProject:
        """Fetch a task project by ID."""
        parsed_id = parse_uuid(project_id, "task project", "id")
        project = (
            db.query(TaskProject)
            .filter(
                TaskProject.id == parsed_id,
                TaskProject.user_id == user_id,
                TaskProject.deleted_at.is_(None),
            )
            .one_or_none()
        )
        if not project:
            raise TaskProjectNotFoundError(project_id)
        return project

    @staticmethod
    def list_task_projects(db: Session, user_id: str) -> list[TaskProject]:
        """List active task projects for a user."""
        return (
            db.query(TaskProject)
            .filter(TaskProject.user_id == user_id, TaskProject.deleted_at.is_(None))
            .order_by(TaskProject.title.asc())
            .all()
        )

    @staticmethod
    def update_task_project(
        db: Session,
        user_id: str,
        project_id: str,
        *,
        title: str | None = None,
        area_id: str | None = None,
        status: str | None = None,
        notes: str | None = None,
    ) -> TaskProject:
        """Update task project metadata."""
        project = TaskService.get_task_project(db, user_id, project_id)
        if title is not None:
            project.title = title
        if area_id is not None:
            project.area_id = parse_optional_uuid(area_id, "task area", "id")
        if status is not None:
            project.status = status
        if notes is not None:
            project.notes = notes
        project.updated_at = datetime.now(UTC)
        return project

    @staticmethod
    def delete_task_project(db: Session, user_id: str, project_id: str) -> TaskProject:
        """Soft-delete a task project."""
        project = TaskService.get_task_project(db, user_id, project_id)
        now = datetime.now(UTC)
        project.deleted_at = now
        project.updated_at = now
        return project

    @staticmethod
    def create_task(
        db: Session,
        user_id: str,
        title: str,
        *,
        status: str = "inbox",
        project_id: str | None = None,
        area_id: str | None = None,
        notes: str | None = None,
        deadline: date | None = None,
        deadline_start: date | None = None,
        scheduled_date: date | None = None,
        tags: list[str] | None = None,
        recurrence_rule: dict[str, Any] | None = None,
        repeating: bool = False,
        repeat_template: bool = False,
        repeat_template_id: str | None = None,
        next_instance_date: date | None = None,
        things_id: str | None = None,
    ) -> Task:
        """Create a new task."""
        now = datetime.now(UTC)
        task = Task(
            user_id=user_id,
            title=title,
            status=status,
            project_id=parse_optional_uuid(project_id, "task project", "id"),
            area_id=parse_optional_uuid(area_id, "task area", "id"),
            notes=notes,
            deadline=deadline,
            deadline_start=deadline_start,
            scheduled_date=scheduled_date,
            tags=tags or [],
            recurrence_rule=recurrence_rule,
            repeating=repeating,
            repeat_template=repeat_template,
            repeat_template_id=parse_optional_uuid(repeat_template_id, "task", "id"),
            next_instance_date=next_instance_date,
            things_id=things_id,
            created_at=now,
            updated_at=now,
            deleted_at=None,
        )
        db.add(task)
        db.flush()
        return task

    @staticmethod
    def get_task(db: Session, user_id: str, task_id: str) -> Task:
        """Fetch a task by ID."""
        parsed_id = parse_uuid(task_id, "task", "id")
        task = (
            db.query(Task)
            .filter(
                Task.id == parsed_id,
                Task.user_id == user_id,
                Task.deleted_at.is_(None),
            )
            .one_or_none()
        )
        if not task:
            raise TaskNotFoundError(task_id)
        return task

    @staticmethod
    def list_tasks(db: Session, user_id: str) -> list[Task]:
        """List active tasks for a user."""
        return (
            db.query(Task)
            .filter(Task.user_id == user_id, Task.deleted_at.is_(None))
            .order_by(Task.created_at.desc())
            .all()
        )

    @staticmethod
    def update_task(
        db: Session,
        user_id: str,
        task_id: str,
        *,
        title: str | None = None,
        status: str | None = None,
        project_id: str | None = None,
        area_id: str | None = None,
        notes: str | None = None,
        deadline: date | None = None,
        deadline_start: date | None = None,
        scheduled_date: date | None = None,
        tags: list[str] | None = None,
        recurrence_rule: dict[str, Any] | None = None,
        repeating: bool | None = None,
        repeat_template: bool | None = None,
        repeat_template_id: str | None = None,
        next_instance_date: date | None = None,
    ) -> Task:
        """Update a task."""
        task = TaskService.get_task(db, user_id, task_id)
        if title is not None:
            task.title = title
        if status is not None:
            task.status = status
        if project_id is not None:
            task.project_id = parse_optional_uuid(project_id, "task project", "id")
        if area_id is not None:
            task.area_id = parse_optional_uuid(area_id, "task area", "id")
        if notes is not None:
            task.notes = notes
        if deadline is not None:
            task.deadline = deadline
        if deadline_start is not None:
            task.deadline_start = deadline_start
        if scheduled_date is not None:
            task.scheduled_date = scheduled_date
        if tags is not None:
            task.tags = tags
            flag_modified(task, "tags")
        if recurrence_rule is not None:
            task.recurrence_rule = recurrence_rule
            flag_modified(task, "recurrence_rule")
        if repeating is not None:
            task.repeating = repeating
        if repeat_template is not None:
            task.repeat_template = repeat_template
        if repeat_template_id is not None:
            task.repeat_template_id = parse_optional_uuid(
                repeat_template_id, "task", "id"
            )
        if next_instance_date is not None:
            task.next_instance_date = next_instance_date
        task.updated_at = datetime.now(UTC)
        return task

    @staticmethod
    def delete_task(db: Session, user_id: str, task_id: str) -> Task:
        """Soft-delete a task."""
        task = TaskService.get_task(db, user_id, task_id)
        now = datetime.now(UTC)
        task.deleted_at = now
        task.updated_at = now
        return task

    @staticmethod
    def complete_task(
        db: Session, user_id: str, task_id: str
    ) -> tuple[Task, Task | None]:
        """Mark a task complete and create the next instance if repeating."""
        task = TaskService.get_task(db, user_id, task_id)
        now = datetime.now(UTC)
        task.status = "completed"
        task.completed_at = now
        task.updated_at = now

        next_task = RecurrenceService.complete_repeating_task(db, task)
        return task, next_task
