"""Tasks router."""

from datetime import UTC, datetime

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import SessionLocal, get_db, set_session_user_id
from api.exceptions import BadRequestError
from api.services.recurrence_service import RecurrenceService
from api.services.task_service import TaskService
from api.services.task_sync_service import TaskSyncService
from api.services.tasks_snapshot_service import TasksSnapshotService
from api.services.user_settings_service import UserSettingsService

router = APIRouter(prefix="/tasks", tags=["tasks"])


def _task_payload(task) -> dict:
    deadline = task.deadline
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
    }


def _project_payload(project) -> dict:
    return {
        "id": str(project.id),
        "title": project.title,
        "areaId": str(project.area_id) if project.area_id else None,
        "status": project.status,
        "updatedAt": project.updated_at.isoformat() if project.updated_at else None,
    }


def _area_payload(area) -> dict:
    return {
        "id": str(area.id),
        "title": area.title,
        "updatedAt": area.updated_at.isoformat() if area.updated_at else None,
    }


def _task_sync_payload(task) -> dict:
    payload = _task_payload(task)
    payload["deletedAt"] = (
        task.deleted_at.isoformat() if getattr(task, "deleted_at", None) else None
    )
    return payload


def _project_sync_payload(project) -> dict:
    payload = _project_payload(project)
    payload["deletedAt"] = (
        project.deleted_at.isoformat() if getattr(project, "deleted_at", None) else None
    )
    return payload


def _area_sync_payload(area) -> dict:
    payload = _area_payload(area)
    payload["deletedAt"] = (
        area.deleted_at.isoformat() if getattr(area, "deleted_at", None) else None
    )
    return payload


def _update_snapshot_background(user_id: str, today_payload: dict) -> None:
    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        try:
            upcoming_tasks, projects, areas = TaskService.list_tasks_by_scope(
                db, user_id, "upcoming"
            )
            upcoming_payload = [_task_payload(task) for task in upcoming_tasks]
            snapshot = TasksSnapshotService.build_snapshot(
                today_tasks=today_payload.get("tasks", []),
                tomorrow_tasks=TasksSnapshotService.filter_tomorrow(upcoming_payload),
                completed_today=[],
                areas=[_area_payload(area) for area in areas],
                projects=[_project_payload(project) for project in projects],
            )
            UserSettingsService.update_tasks_snapshot(db, user_id, snapshot)
        except Exception:
            return


@router.get("/lists/{scope}")
async def get_tasks_list(
    scope: str,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch a task list for the requested scope."""
    set_session_user_id(db, user_id)
    tasks, projects, areas = TaskService.list_tasks_by_scope(db, user_id, scope)
    response = {
        "scope": scope,
        "generatedAt": datetime.now(UTC).isoformat(),
        "tasks": [_task_payload(task) for task in tasks],
        "projects": [_project_payload(project) for project in projects],
        "areas": [_area_payload(area) for area in areas],
    }
    if scope == "today":
        background_tasks.add_task(_update_snapshot_background, user_id, response)
    return response


@router.get("/search")
async def search_tasks(
    query: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Search tasks by text query."""
    query = query.strip()
    if not query:
        raise BadRequestError("query required")
    set_session_user_id(db, user_id)
    tasks = TaskService.search_tasks(db, user_id, query)
    return {
        "scope": "search",
        "generatedAt": datetime.now(UTC).isoformat(),
        "tasks": [_task_payload(task) for task in tasks],
    }


@router.post("/apply")
async def apply_task_operation(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Apply task operations."""
    set_session_user_id(db, user_id)
    operations = request.get("operations")
    op_list = operations if isinstance(operations, list) else [request]
    result = TaskSyncService.apply_operations(db, user_id, op_list)
    db.commit()
    return {
        "applied": result.applied_ids,
        "tasks": [_task_payload(task) for task in result.tasks],
        "nextTasks": [_task_payload(task) for task in result.next_tasks],
        "conflicts": [],
        "serverUpdatedSince": datetime.now(UTC).isoformat(),
    }


@router.post("/sync")
async def sync_tasks(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Apply offline operations and return updates since the last sync."""
    set_session_user_id(db, user_id)
    result = TaskSyncService.sync_operations(db, user_id, request)
    db.commit()
    return {
        "applied": result.applied_ids,
        "tasks": [_task_payload(task) for task in result.tasks],
        "nextTasks": [_task_payload(task) for task in result.next_tasks],
        "conflicts": result.conflicts,
        "updates": {
            "tasks": [_task_sync_payload(task) for task in result.updated_tasks],
            "projects": [
                _project_sync_payload(project) for project in result.updated_projects
            ],
            "areas": [_area_sync_payload(area) for area in result.updated_areas],
        },
        "serverUpdatedSince": result.server_updated_since.isoformat(),
    }


@router.post("/areas")
async def create_task_area(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Create a task area."""
    title = str(request.get("title") or "").strip()
    if not title:
        raise BadRequestError("title required")
    set_session_user_id(db, user_id)
    area = TaskService.create_task_area(db, user_id, title)
    db.commit()
    return _area_payload(area)


@router.post("/projects")
async def create_task_project(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Create a task project."""
    title = str(request.get("title") or "").strip()
    if not title:
        raise BadRequestError("title required")
    area_id = request.get("areaId")
    set_session_user_id(db, user_id)
    project = TaskService.create_task_project(db, user_id, title, area_id=area_id)
    db.commit()
    return _project_payload(project)


@router.get("/projects/{project_id}/tasks")
async def get_project_tasks(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch tasks for a project."""
    set_session_user_id(db, user_id)
    tasks = TaskService.list_tasks_by_project(db, user_id, project_id)
    projects = TaskService.list_task_projects(db, user_id)
    areas = TaskService.list_task_areas(db, user_id)
    return {
        "scope": "project",
        "generatedAt": datetime.now(UTC).isoformat(),
        "tasks": [_task_payload(task) for task in tasks],
        "projects": [_project_payload(project) for project in projects],
        "areas": [_area_payload(area) for area in areas],
    }


@router.get("/areas/{area_id}/tasks")
async def get_area_tasks(
    area_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch tasks for an area."""
    set_session_user_id(db, user_id)
    tasks = TaskService.list_tasks_by_area(db, user_id, area_id)
    projects = TaskService.list_task_projects(db, user_id)
    areas = TaskService.list_task_areas(db, user_id)
    return {
        "scope": "area",
        "generatedAt": datetime.now(UTC).isoformat(),
        "tasks": [_task_payload(task) for task in tasks],
        "projects": [_project_payload(project) for project in projects],
        "areas": [_area_payload(area) for area in areas],
    }


@router.get("/counts")
async def get_counts(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch task counts for list badges."""
    set_session_user_id(db, user_id)
    counts = TaskService.get_counts(db, user_id)
    return {
        "generatedAt": datetime.now(UTC).isoformat(),
        "counts": {
            "inbox": counts.inbox,
            "today": counts.today,
            "upcoming": counts.upcoming,
        },
        "projects": [
            {"id": project_id, "count": count}
            for project_id, count in counts.project_counts
        ],
        "areas": [
            {"id": area_id, "count": count} for area_id, count in counts.area_counts
        ],
    }
