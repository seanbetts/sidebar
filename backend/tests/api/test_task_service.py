import uuid
from datetime import date

import pytest
from api.db.base import Base
from api.exceptions import TaskNotFoundError
from api.services.task_service import TaskService
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
        tags=["urgent", "work"],
        recurrence_rule={"type": "daily", "interval": 1},
    )
    db_session.commit()

    refreshed = TaskService.get_task(db_session, "user", str(task.id))
    assert refreshed.tags == ["urgent", "work"]
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
        scheduled_date=date(2026, 1, 1),
        deadline=date(2026, 1, 2),
        deadline_start=date(2025, 12, 31),
    )
    db_session.commit()

    tasks = TaskService.list_tasks(db_session, "user")
    assert tasks[0].scheduled_date == date(2026, 1, 1)
    assert tasks[0].deadline == date(2026, 1, 2)
    assert tasks[0].deadline_start == date(2025, 12, 31)
