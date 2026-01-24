"""Service layer for native task system."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, joinedload
from sqlalchemy.orm.attributes import flag_modified

from api.exceptions import (
    TaskGroupNotFoundError,
    TaskNotFoundError,
    TaskProjectNotFoundError,
)
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_project import TaskProject
from api.services.recurrence_service import RecurrenceService
from api.utils.validation import parse_optional_uuid, parse_uuid


@dataclass
class TaskCounts:
    """Aggregated task counts for list badges."""

    inbox: int
    today: int
    upcoming: int
    project_counts: list[tuple[str, int]]
    group_counts: list[tuple[str, int]]


@dataclass
class TaskService:
    """Service layer for task CRUD operations."""

    @staticmethod
    def _task_query_with_relations(db: Session):
        return db.query(Task).options(
            joinedload(Task.project).joinedload(TaskProject.group),
            joinedload(Task.group),
        )

    @staticmethod
    def create_task_group(
        db: Session,
        user_id: str,
        title: str,
        *,
        source_id: str | None = None,
    ) -> TaskGroup:
        """Create a new task group.

        Args:
            db: Database session.
            user_id: Current user ID.
            title: Group title.
            source_id: Optional external source identifier.

        Returns:
            Newly created TaskGroup.
        """
        now = datetime.now(UTC)
        group = TaskGroup(
            user_id=user_id,
            title=title,
            source_id=source_id,
            created_at=now,
            updated_at=now,
            deleted_at=None,
        )
        db.add(group)
        db.flush()
        return group

    @staticmethod
    def get_task_group(db: Session, user_id: str, group_id: str) -> TaskGroup:
        """Fetch a task group by ID.

        Args:
            db: Database session.
            user_id: Current user ID.
            group_id: Task group ID.

        Returns:
            TaskGroup record.

        Raises:
            TaskGroupNotFoundError: If no matching group is found.
        """
        parsed_id = parse_uuid(group_id, "task group", "id")
        group = (
            db.query(TaskGroup)
            .filter(
                TaskGroup.id == parsed_id,
                TaskGroup.user_id == user_id,
                TaskGroup.deleted_at.is_(None),
            )
            .one_or_none()
        )
        if not group:
            raise TaskGroupNotFoundError(group_id)
        return group

    @staticmethod
    def list_task_groups(db: Session, user_id: str) -> list[TaskGroup]:
        """List active task groups for a user."""
        return (
            db.query(TaskGroup)
            .filter(TaskGroup.user_id == user_id, TaskGroup.deleted_at.is_(None))
            .order_by(TaskGroup.title.asc())
            .all()
        )

    @staticmethod
    def update_task_group(
        db: Session,
        user_id: str,
        group_id: str,
        *,
        title: str,
    ) -> TaskGroup:
        """Update task group metadata."""
        group = TaskService.get_task_group(db, user_id, group_id)
        group.title = title
        group.updated_at = datetime.now(UTC)
        return group

    @staticmethod
    def delete_task_group(db: Session, user_id: str, group_id: str) -> TaskGroup:
        """Soft-delete a task group along with related projects and tasks."""
        group = TaskService.get_task_group(db, user_id, group_id)
        now = datetime.now(UTC)
        projects = (
            db.query(TaskProject)
            .filter(
                TaskProject.user_id == user_id,
                TaskProject.group_id == group.id,
                TaskProject.deleted_at.is_(None),
            )
            .all()
        )
        project_ids = [project.id for project in projects]
        for project in projects:
            project.deleted_at = now
            project.updated_at = now

        tasks_query = db.query(Task).filter(
            Task.user_id == user_id,
            Task.deleted_at.is_(None),
        )
        if project_ids:
            tasks_query = tasks_query.filter(
                or_(Task.group_id == group.id, Task.project_id.in_(project_ids))
            )
        else:
            tasks_query = tasks_query.filter(Task.group_id == group.id)
        tasks = tasks_query.all()
        for task in tasks:
            task.deleted_at = now
            task.updated_at = now
        group.deleted_at = now
        group.updated_at = now
        return group

    @staticmethod
    def create_task_project(
        db: Session,
        user_id: str,
        title: str,
        *,
        group_id: str | None = None,
        status: str = "active",
        notes: str | None = None,
        source_id: str | None = None,
    ) -> TaskProject:
        """Create a new task project."""
        now = datetime.now(UTC)
        project = TaskProject(
            user_id=user_id,
            title=title,
            group_id=parse_optional_uuid(group_id, "task group", "id"),
            status=status,
            notes=notes,
            source_id=source_id,
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
        group_id: str | None = None,
        status: str | None = None,
        notes: str | None = None,
    ) -> TaskProject:
        """Update task project metadata."""
        project = TaskService.get_task_project(db, user_id, project_id)
        if title is not None:
            project.title = title
        if group_id is not None:
            project.group_id = parse_optional_uuid(group_id, "task group", "id")
        if status is not None:
            project.status = status
        if notes is not None:
            project.notes = notes
        project.updated_at = datetime.now(UTC)
        return project

    @staticmethod
    def delete_task_project(db: Session, user_id: str, project_id: str) -> TaskProject:
        """Soft-delete a task project along with related tasks."""
        project = TaskService.get_task_project(db, user_id, project_id)
        now = datetime.now(UTC)
        tasks = (
            db.query(Task)
            .filter(
                Task.user_id == user_id,
                Task.project_id == project.id,
                Task.deleted_at.is_(None),
            )
            .all()
        )
        for task in tasks:
            task.deleted_at = now
            task.updated_at = now
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
        group_id: str | None = None,
        notes: str | None = None,
        deadline: date | None = None,
        recurrence_rule: dict[str, Any] | None = None,
        repeating: bool = False,
        repeat_template: bool = False,
        repeat_template_id: str | None = None,
        next_instance_date: date | None = None,
        source_id: str | None = None,
    ) -> Task:
        """Create a new task."""
        now = datetime.now(UTC)
        task = Task(
            user_id=user_id,
            title=title,
            status=status,
            project_id=parse_optional_uuid(project_id, "task project", "id"),
            group_id=parse_optional_uuid(group_id, "task group", "id"),
            notes=notes,
            deadline=deadline,
            recurrence_rule=recurrence_rule,
            repeating=repeating,
            repeat_template=repeat_template,
            repeat_template_id=parse_optional_uuid(repeat_template_id, "task", "id"),
            next_instance_date=next_instance_date,
            source_id=source_id,
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
            TaskService._task_query_with_relations(db)
            .filter(Task.user_id == user_id, Task.deleted_at.is_(None))
            .order_by(Task.created_at.desc())
            .all()
        )

    @staticmethod
    def list_tasks_by_scope(
        db: Session, user_id: str, scope: str
    ) -> tuple[list[Task], list[TaskProject], list[TaskGroup]]:
        """List tasks by scope with related groups/projects."""
        today = date.today()
        base_query = TaskService._task_query_with_relations(db).filter(
            Task.user_id == user_id,
            Task.deleted_at.is_(None),
            Task.status.notin_(["completed", "trashed"]),
        )

        if scope == "today":
            query = base_query.filter(
                Task.status != "someday",
                or_(
                    Task.deadline <= today,
                ),
            )
        elif scope == "upcoming":
            query = base_query.filter(
                Task.status != "someday",
                or_(
                    Task.deadline > today,
                    Task.deadline.is_(None),
                ),
            )
        elif scope == "inbox":
            query = base_query.filter(Task.status == "inbox")
        else:
            query = base_query

        tasks = query.order_by(Task.updated_at.desc()).all()
        projects = TaskService.list_task_projects(db, user_id)
        groups = TaskService.list_task_groups(db, user_id)
        return tasks, projects, groups

    @staticmethod
    def list_tasks_by_project(db: Session, user_id: str, project_id: str) -> list[Task]:
        """List tasks for a specific project."""
        parsed_id = parse_uuid(project_id, "project", "id")
        return (
            TaskService._task_query_with_relations(db)
            .filter(
                Task.user_id == user_id,
                Task.project_id == parsed_id,
                Task.deleted_at.is_(None),
                Task.status.notin_(["completed", "trashed"]),
            )
            .order_by(Task.updated_at.desc())
            .all()
        )

    @staticmethod
    def list_tasks_by_group(db: Session, user_id: str, group_id: str) -> list[Task]:
        """List tasks for a specific group."""
        parsed_id = parse_uuid(group_id, "task group", "id")
        return (
            TaskService._task_query_with_relations(db)
            .filter(
                Task.user_id == user_id,
                or_(
                    Task.group_id == parsed_id,
                    Task.project.has(TaskProject.group_id == parsed_id),
                ),
                Task.deleted_at.is_(None),
                Task.status.notin_(["completed", "trashed"]),
            )
            .order_by(Task.updated_at.desc())
            .all()
        )

    @staticmethod
    def search_tasks(db: Session, user_id: str, query: str) -> list[Task]:
        """Search tasks by title or notes."""
        return (
            TaskService._task_query_with_relations(db)
            .filter(
                Task.user_id == user_id,
                Task.deleted_at.is_(None),
                Task.status != "trashed",
                Task.status != "completed",
                or_(
                    Task.title.ilike(f"%{query}%"),
                    Task.notes.ilike(f"%{query}%"),
                ),
            )
            .order_by(Task.updated_at.desc())
            .all()
        )

    @staticmethod
    def get_counts(db: Session, user_id: str) -> TaskCounts:
        """Compute badge counts for task lists."""
        today = date.today()
        base = (
            db.query(Task)
            .filter(
                Task.user_id == user_id,
                Task.deleted_at.is_(None),
                Task.status.notin_(["completed", "trashed"]),
            )
            .subquery()
        )

        inbox_count = (
            db.query(func.count())
            .select_from(base)
            .filter(base.c.status == "inbox")
            .scalar()
            or 0
        )
        today_count = (
            db.query(func.count())
            .select_from(base)
            .filter(
                base.c.status != "someday",
                or_(
                    base.c.deadline <= today,
                ),
            )
            .scalar()
            or 0
        )
        upcoming_count = (
            db.query(func.count())
            .select_from(base)
            .filter(
                base.c.status != "someday",
                or_(
                    base.c.deadline > today,
                    base.c.deadline.is_(None),
                ),
            )
            .scalar()
            or 0
        )

        project_counts = (
            db.query(Task.project_id, func.count(Task.id))
            .filter(
                Task.user_id == user_id,
                Task.deleted_at.is_(None),
                Task.status.notin_(["completed", "trashed"]),
                Task.project_id.isnot(None),
            )
            .group_by(Task.project_id)
            .all()
        )
        group_id = func.coalesce(Task.group_id, TaskProject.group_id)
        group_counts = (
            db.query(group_id, func.count(Task.id))
            .outerjoin(TaskProject, Task.project_id == TaskProject.id)
            .filter(
                Task.user_id == user_id,
                Task.deleted_at.is_(None),
                Task.status.notin_(["completed", "trashed"]),
                group_id.isnot(None),
            )
            .group_by(group_id)
            .all()
        )

        return TaskCounts(
            inbox=inbox_count,
            today=today_count,
            upcoming=upcoming_count,
            project_counts=[(str(pid), count) for pid, count in project_counts],
            group_counts=[(str(gid), count) for gid, count in group_counts],
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
        group_id: str | None = None,
        notes: str | None = None,
        deadline: date | None = None,
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
        if group_id is not None:
            task.group_id = parse_optional_uuid(group_id, "task group", "id")
        if notes is not None:
            task.notes = notes
        if deadline is not None:
            task.deadline = deadline
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
    def set_task_recurrence(
        db: Session,
        user_id: str,
        task_id: str,
        *,
        recurrence_rule: dict[str, Any] | None,
        anchor_date: date | None,
    ) -> list[Task]:
        """Update recurrence for a task and its template."""
        task = TaskService.get_task(db, user_id, task_id)
        if recurrence_rule:
            recurrence_rule = dict(recurrence_rule)
            recurrence_rule["interval"] = max(
                1, int(recurrence_rule.get("interval") or 1)
            )
        template_id = task.repeat_template_id or task.id
        template = (
            TaskService.get_task(db, user_id, str(template_id))
            if template_id != task.id
            else task
        )
        now = datetime.now(UTC)

        def apply_rule(target: Task) -> None:
            target.recurrence_rule = recurrence_rule
            flag_modified(target, "recurrence_rule")
            target.repeating = bool(recurrence_rule)
            if recurrence_rule:
                if target.repeat_template_id is None:
                    target.repeat_template_id = template_id
            else:
                target.repeat_template_id = None
                target.repeat_template = False
            target.updated_at = now

        apply_rule(template)
        if task.id != template.id:
            apply_rule(task)

        if recurrence_rule and anchor_date:
            if task.deadline is None:
                task.deadline = anchor_date
            if task.id == template.id:
                task.updated_at = now

        return [template] if task.id == template.id else [template, task]

    @staticmethod
    def clear_task_due(db: Session, user_id: str, task_id: str) -> Task:
        """Clear due and scheduled dates for a task."""
        task = TaskService.get_task(db, user_id, task_id)
        task.deadline = None
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
    def trash_task_series(db: Session, user_id: str, task_id: str) -> list[Task]:
        """Soft-delete a task and any repeat instances in its series."""
        task = TaskService.get_task(db, user_id, task_id)
        template_id = task.repeat_template_id or task.id
        now = datetime.now(UTC)

        tasks = (
            db.query(Task)
            .filter(
                Task.user_id == user_id,
                Task.deleted_at.is_(None),
                or_(Task.id == template_id, Task.repeat_template_id == template_id),
            )
            .all()
        )
        if not tasks:
            return []

        for item in tasks:
            item.status = "trashed"
            item.trashed_at = now
            item.deleted_at = now
            item.updated_at = now

        return tasks

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

    @staticmethod
    def list_completed_today(db: Session, user_id: str) -> list[Task]:
        """List tasks completed today."""
        today_start = datetime.combine(date.today(), datetime.min.time(), tzinfo=UTC)
        return (
            TaskService._task_query_with_relations(db)
            .filter(
                Task.user_id == user_id,
                Task.status == "completed",
                Task.completed_at >= today_start,
                Task.deleted_at.is_(None),
            )
            .order_by(Task.completed_at.desc())
            .all()
        )
