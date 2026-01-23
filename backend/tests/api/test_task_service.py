import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from api.db.base import Base
from api.exceptions import TaskNotFoundError
from api.services.task_service import TaskService
from api.services.task_sync_service import TaskSyncService
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


@pytest.fixture
def db_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"

    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)

    Session = sessionmaker(bind=connection)
    session = Session()

    try:
        yield session
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()


def test_create_task_area_project_task(db_session):
    area = TaskService.create_task_area(db_session, "user", "Work")
    project = TaskService.create_task_project(
        db_session, "user", "Alpha", area_id=str(area.id)
    )
    task = TaskService.create_task(
        db_session,
        "user",
        "First task",
        project_id=str(project.id),
        status="inbox",
    )

    db_session.commit()

    fetched = TaskService.get_task(db_session, "user", str(task.id))
    assert fetched.title == "First task"
    assert fetched.project_id == project.id

    projects = TaskService.list_task_projects(db_session, "user")
    areas = TaskService.list_task_areas(db_session, "user")
    assert projects[0].id == project.id
    assert areas[0].id == area.id


def test_update_task_updates_jsonb(db_session):
    task = TaskService.create_task(db_session, "user", "Tagged task")
    db_session.commit()

    TaskService.update_task(
        db_session,
        "user",
        str(task.id),
        recurrence_rule={"type": "daily", "interval": 1},
    )
    db_session.commit()

    refreshed = TaskService.get_task(db_session, "user", str(task.id))
    assert refreshed.recurrence_rule == {"type": "daily", "interval": 1}


def test_delete_task_hides_from_list(db_session):
    task = TaskService.create_task(db_session, "user", "Disposable task")
    db_session.commit()

    TaskService.delete_task(db_session, "user", str(task.id))
    db_session.commit()

    assert TaskService.list_tasks(db_session, "user") == []


def test_get_task_not_found_raises(db_session):
    with pytest.raises(TaskNotFoundError):
        TaskService.get_task(db_session, "user", str(uuid.uuid4()))


def test_create_task_dates(db_session):
    TaskService.create_task(
        db_session,
        "user",
        "Scheduled task",
        deadline=date(2026, 1, 2),
    )
    db_session.commit()

    tasks = TaskService.list_tasks(db_session, "user")
    assert tasks[0].deadline == date(2026, 1, 2)


def test_set_task_recurrence_sets_anchor(db_session):
    task = TaskService.create_task(db_session, "user", "Recurring task")
    db_session.commit()

    TaskService.set_task_recurrence(
        db_session,
        "user",
        str(task.id),
        recurrence_rule={"type": "weekly", "interval": 2, "weekday": 1},
        anchor_date=date(2026, 1, 5),
    )
    db_session.commit()

    refreshed = TaskService.get_task(db_session, "user", str(task.id))
    assert refreshed.repeating is True
    assert refreshed.recurrence_rule == {"type": "weekly", "interval": 2, "weekday": 1}
    assert refreshed.repeat_template_id == task.id
    assert refreshed.deadline == date(2026, 1, 5)


def test_clear_task_due(db_session):
    task = TaskService.create_task(
        db_session,
        "user",
        "Dated task",
        deadline=date(2026, 1, 2),
    )
    db_session.commit()

    TaskService.clear_task_due(db_session, "user", str(task.id))
    db_session.commit()

    refreshed = TaskService.get_task(db_session, "user", str(task.id))
    assert refreshed.deadline is None


def test_list_tasks_by_scope_and_counts(db_session):
    today = date.today()
    TaskService.create_task(
        db_session, "user", "Inbox task", status="inbox"
    )
    TaskService.create_task(
        db_session,
        "user",
        "Today task",
        status="inbox",
        deadline=today,
    )
    TaskService.create_task(
        db_session,
        "user",
        "Upcoming task",
        status="inbox",
        deadline=today + timedelta(days=1),
    )
    db_session.commit()

    today_tasks, _, _ = TaskService.list_tasks_by_scope(db_session, "user", "today")
    upcoming_tasks, _, _ = TaskService.list_tasks_by_scope(
        db_session, "user", "upcoming"
    )
    inbox_tasks, _, _ = TaskService.list_tasks_by_scope(db_session, "user", "inbox")

    assert any(task.title == "Today task" for task in today_tasks)
    assert any(task.title == "Upcoming task" for task in upcoming_tasks)
    assert any(task.title == "Inbox task" for task in inbox_tasks)

    counts = TaskService.get_counts(db_session, "user")
    assert counts.inbox == 3


def test_apply_operations_idempotent(db_session):
    operation = {
        "operation_id": "op-1",
        "op": "add",
        "title": "New Task",
    }
    result = TaskSyncService.apply_operations(db_session, "user", [operation])
    db_session.commit()

    assert result.applied_ids == ["op-1"]
    assert len(result.tasks) == 1

    second = TaskSyncService.apply_operations(db_session, "user", [operation])
    db_session.commit()

    assert second.applied_ids == ["op-1"]
    assert len(TaskService.list_tasks(db_session, "user")) == 1


def test_sync_operations_returns_updates(db_session):
    task = TaskService.create_task(db_session, "user", "Sync task")
    db_session.commit()

    last_sync = datetime.now(UTC)
    TaskService.update_task(db_session, "user", str(task.id), title="Synced")
    db_session.commit()

    payload = {"last_sync": last_sync.isoformat(), "operations": []}
    result = TaskSyncService.sync_operations(db_session, "user", payload)

    assert any(item.id == task.id for item in result.updated_tasks)


def test_sync_operations_conflict(db_session):
    task = TaskService.create_task(db_session, "user", "Original")
    db_session.commit()

    stale_time = (datetime.now(UTC) - timedelta(minutes=10)).isoformat()
    payload = {
        "last_sync": None,
        "operations": [
            {
                "operation_id": "op-2",
                "op": "rename",
                "id": str(task.id),
                "title": "Updated",
                "client_updated_at": stale_time,
            }
        ],
    }
    result = TaskSyncService.sync_operations(db_session, "user", payload)
    db_session.commit()

    db_session.refresh(task)
    assert task.title == "Original"
    assert result.conflicts
