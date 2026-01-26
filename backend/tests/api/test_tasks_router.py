from datetime import UTC, date, datetime, timedelta

from api.config import settings
from api.db.dependencies import DEFAULT_USER_ID
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_project import TaskProject


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_tasks_list_today(test_client, test_db):
    group = TaskGroup(
        user_id=DEFAULT_USER_ID,
        title="Work",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    project = TaskProject(
        user_id=DEFAULT_USER_ID,
        title="Alpha",
        group_id=group.id,
        status="active",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(group)
    test_db.flush()
    project.group_id = group.id
    test_db.add(project)

    today = date.today()
    task_today = Task(
        user_id=DEFAULT_USER_ID,
        title="Today task",
        status="inbox",
        deadline=today,
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
    assert payload.get("groups")
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
                deadline=today,
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
            Task(
                user_id=DEFAULT_USER_ID,
                title="Done",
                status="completed",
                completed_at=datetime.now(UTC),
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
    assert payload["counts"]["completed"] == 1


def test_tasks_group_and_project_payloads(test_client, test_db):
    group = TaskGroup(
        user_id=DEFAULT_USER_ID,
        title="Home",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(group)
    test_db.flush()
    project = TaskProject(
        user_id=DEFAULT_USER_ID,
        title="Household",
        group_id=group.id,
        status="active",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    task = Task(
        user_id=DEFAULT_USER_ID,
        title="Vacuum",
        status="inbox",
        project_id=project.id,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add_all([project, task])
    test_db.commit()

    group_response = test_client.get(
        f"/api/v1/tasks/groups/{group.id}/tasks", headers=_auth_headers()
    )
    assert group_response.status_code == 200
    group_payload = group_response.json()
    assert group_payload["scope"] == "group"
    assert group_payload["groups"]
    assert group_payload["projects"]
    assert any(item["title"] == "Vacuum" for item in group_payload["tasks"])

    project_response = test_client.get(
        f"/api/v1/tasks/projects/{project.id}/tasks", headers=_auth_headers()
    )
    assert project_response.status_code == 200
    project_payload = project_response.json()
    assert project_payload["scope"] == "project"
    assert project_payload["groups"]
    assert project_payload["projects"]
    assert any(item["title"] == "Vacuum" for item in project_payload["tasks"])


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


def test_tasks_sync_returns_updates(test_client, test_db):
    task = Task(
        user_id=DEFAULT_USER_ID,
        title="Sync me",
        status="inbox",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(task)
    test_db.commit()

    last_sync = (datetime.now(UTC) - timedelta(minutes=1)).isoformat()
    response = test_client.post(
        "/api/v1/tasks/sync",
        json={"last_sync": last_sync, "operations": []},
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    payload = response.json()
    assert any(item["title"] == "Sync me" for item in payload["updates"]["tasks"])
    assert payload["serverUpdatedSince"]


def test_tasks_create_group_and_project(test_client, test_db):
    response = test_client.post(
        "/api/v1/tasks/groups",
        json={"title": "Personal"},
        headers=_auth_headers(),
    )
    assert response.status_code == 200
    group_payload = response.json()
    assert group_payload["title"] == "Personal"

    project_response = test_client.post(
        "/api/v1/tasks/projects",
        json={"title": "Habits", "groupId": group_payload["id"]},
        headers=_auth_headers(),
    )
    assert project_response.status_code == 200
    project_payload = project_response.json()
    assert project_payload["title"] == "Habits"
    assert project_payload["groupId"] == group_payload["id"]
