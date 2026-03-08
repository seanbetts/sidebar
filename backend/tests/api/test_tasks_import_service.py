from datetime import date

from api.models.task import Task
from api.models.task_project import TaskProject
from api.services.tasks_import_service import TasksImportService


def test_import_from_payload_filters_and_maps(test_db):
    payload = {
        "groups": [{"id": "g1", "title": "Group", "updatedAt": "2026-01-01T00:00:00Z"}],
        "projects": [
            {
                "id": "p1",
                "title": "Project",
                "groupId": "g1",
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
                "groupId": "g1",
                "deadline": "2026-01-02T00:00:00Z",
                "scheduledDate": "2026-01-01T00:00:00Z",
                "repeating": True,
                "recurrenceRule": {"type": "daily", "interval": 1},
                "updatedAt": "2026-01-01T00:00:00Z",
            },
            {"id": "t2", "title": "Done", "status": "completed"},
        ],
    }

    stats = TasksImportService.import_from_payload(test_db, "user", payload)
    test_db.commit()

    assert stats.groups_imported == 1
    assert stats.projects_imported == 1
    assert stats.projects_skipped == 1
    assert stats.tasks_imported == 1
    assert stats.tasks_skipped == 1

    task = test_db.query(Task).one()
    assert task.status == "active"
    assert task.deadline == date(2026, 1, 2)
    assert task.repeating is True
    assert task.recurrence_rule == {"type": "daily", "interval": 1}

    project = test_db.query(TaskProject).one()
    assert project.title == "Project"
