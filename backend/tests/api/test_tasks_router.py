from datetime import UTC, date, datetime, timedelta

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.models.task import Task
from api.models.task_area import TaskArea
from api.models.task_project import TaskProject


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_tasks_list_today(test_client, test_db):
    area = TaskArea(
        user_id=DEFAULT_USER_ID,
        title="Work",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    project = TaskProject(
        user_id=DEFAULT_USER_ID,
        title="Alpha",
        area_id=area.id,
        status="active",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(area)
    test_db.flush()
    project.area_id = area.id
    test_db.add(project)

    today = date.today()
    task_today = Task(
        user_id=DEFAULT_USER_ID,
        title="Today task",
        status="inbox",
        scheduled_date=today,
        project_id=project.id,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    task_inbox = Task(
        user_id=DEFAULT_USER_ID,
        title="Inbox task",
        status="inbox",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add_all([task_today, task_inbox])
    test_db.commit()

    response = test_client.get("/api/v1/tasks/lists/today", headers=_auth_headers())
    assert response.status_code == 200
    payload = response.json()
    titles = {task["title"] for task in payload.get("tasks", [])}
    assert "Today task" in titles
    assert "Inbox task" not in titles
    assert payload.get("areas")
    assert payload.get("projects")


def test_tasks_search(test_client, test_db):
    task = Task(
        user_id=DEFAULT_USER_ID,
        title="Find me",
        notes="Searchable",
        status="inbox",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(task)
    test_db.commit()

    response = test_client.get(
        "/api/v1/tasks/search", params={"query": "Find"}, headers=_auth_headers()
    )
    assert response.status_code == 200
    payload = response.json()
    assert any(item["title"] == "Find me" for item in payload.get("tasks", []))


def test_tasks_counts(test_client, test_db):
    today = date.today()
    test_db.add_all(
        [
            Task(
                user_id=DEFAULT_USER_ID,
                title="Inbox",
                status="inbox",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
            Task(
                user_id=DEFAULT_USER_ID,
                title="Today",
                status="inbox",
                scheduled_date=today,
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
            Task(
                user_id=DEFAULT_USER_ID,
                title="Upcoming",
                status="inbox",
                deadline=today + timedelta(days=2),
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
        ]
    )
    test_db.commit()

    response = test_client.get("/api/v1/tasks/counts", headers=_auth_headers())
    assert response.status_code == 200
    payload = response.json()
    assert payload["counts"]["inbox"] == 3
    assert payload["counts"]["today"] == 1
    assert payload["counts"]["upcoming"] == 1


def test_tasks_apply_idempotent(test_client, test_db):
    request = {"op": "add", "title": "New Task", "operation_id": "op-1"}
    response = test_client.post(
        "/api/v1/tasks/apply", json=request, headers=_auth_headers()
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["applied"] == ["op-1"]
    assert len(payload["tasks"]) == 1

    second = test_client.post(
        "/api/v1/tasks/apply", json=request, headers=_auth_headers()
    )
    assert second.status_code == 200
    payload_second = second.json()
    assert payload_second["applied"] == ["op-1"]
    assert payload_second["tasks"] == []
