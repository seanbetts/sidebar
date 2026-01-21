import uuid
from datetime import date

from api.db.base import Base
from api.models.task import Task
from api.models.task_project import TaskProject
from api.services.tasks_import_service import TasksImportService
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


def _build_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"
    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)
    Session = sessionmaker(bind=connection)
    session = Session()
    return session, connection, schema


def test_import_from_bridge_filters_and_maps(test_db_engine):
    session, connection, schema = _build_session(test_db_engine)
    try:
        payload = {
            "areas": [
                {"id": "a1", "title": "Area", "updatedAt": "2026-01-01T00:00:00Z"}
            ],
            "projects": [
                {
                    "id": "p1",
                    "title": "Project",
                    "areaId": "a1",
                    "status": "active",
                    "updatedAt": "2026-01-01T00:00:00Z",
                },
                {"id": "p2", "title": "Done", "status": "completed"},
            ],
            "tasks": [
                {
                    "id": "t1",
                    "title": "Task",
                    "status": "today",
                    "projectId": "p1",
                    "areaId": "a1",
                    "deadline": "2026-01-02T00:00:00Z",
                    "deadlineStart": "2026-01-01T00:00:00Z",
                    "tags": ["urgent"],
                    "repeating": True,
                    "updatedAt": "2026-01-01T00:00:00Z",
                },
                {"id": "t2", "title": "Done", "status": "completed"},
            ],
        }

        stats = TasksImportService.import_from_bridge(session, "user", payload)
        session.commit()

        assert stats.areas_imported == 1
        assert stats.projects_imported == 1
        assert stats.projects_skipped == 1
        assert stats.tasks_imported == 1
        assert stats.tasks_skipped == 1

        task = session.query(Task).one()
        assert task.status == "inbox"
        assert task.deadline == date(2026, 1, 2)
        assert task.deadline_start == date(2026, 1, 1)
        assert task.tags == ["urgent"]
        assert task.repeating is True

        project = session.query(TaskProject).one()
        assert project.title == "Project"
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()
