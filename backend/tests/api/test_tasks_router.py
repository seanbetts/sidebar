import os
from datetime import UTC, date, datetime, timedelta

from api.routers import tasks as tasks_router
from api.config import settings
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_project import TaskProject

TEST_USER_ID = os.environ["TEST_USER_ID"]


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_tasks_list_today(test_client, test_db):
    group = TaskGroup(
        user_id=TEST_USER_ID,
        title="Work",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    project = TaskProject(
        user_id=TEST_USER_ID,
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
        user_id=TEST_USER_ID,
        title="Today task",
        status="active",
        deadline=today,
        project_id=project.id,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    task_undated = Task(
        user_id=TEST_USER_ID,
        title="Undated task",
        status="active",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add_all([task_today, task_undated])
    test_db.commit()

    response = test_client.get("/api/v1/tasks/lists/today", headers=_auth_headers())
    assert response.status_code == 200
    payload = response.json()
    titles = {task["title"] for task in payload.get("tasks", [])}
    assert "Today task" in titles
    assert "Undated task" not in titles
    assert payload.get("groups")
    assert payload.get("projects")


def test_tasks_search(test_client, test_db):
    task = Task(
        user_id=TEST_USER_ID,
        title="Find me",
        notes="Searchable",
        status="active",
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


def test_tasks_search_escapes_like_wildcards(test_client, test_db):
    test_db.add_all(
        [
            Task(
                user_id=TEST_USER_ID,
                title="Literal 100% match",
                notes="Contains a percent sign",
                status="active",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
            Task(
                user_id=TEST_USER_ID,
                title="Plain task",
                notes="No wildcard characters",
                status="active",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
        ]
    )
    test_db.commit()

    response = test_client.get(
        "/api/v1/tasks/search",
        params={"query": "%"},
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert [item["title"] for item in payload["tasks"]] == ["Literal 100% match"]


def test_tasks_counts(test_client, test_db):
    today = date.today()
    test_db.add_all(
        [
            Task(
                user_id=TEST_USER_ID,
                title="Undated",
                status="active",
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
            Task(
                user_id=TEST_USER_ID,
                title="Today",
                status="active",
                deadline=today,
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
            Task(
                user_id=TEST_USER_ID,
                title="Upcoming",
                status="active",
                deadline=today + timedelta(days=2),
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            ),
            Task(
                user_id=TEST_USER_ID,
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
    assert "inbox" not in payload["counts"]
    assert payload["counts"]["today"] == 1
    assert payload["counts"]["upcoming"] == 1
    assert payload["counts"]["completed"] == 1


def test_tasks_group_and_project_payloads(test_client, test_db):
    group = TaskGroup(
        user_id=TEST_USER_ID,
        title="Home",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(group)
    test_db.flush()
    project = TaskProject(
        user_id=TEST_USER_ID,
        title="Household",
        group_id=group.id,
        status="active",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(project)
    test_db.flush()
    task = Task(
        user_id=TEST_USER_ID,
        title="Vacuum",
        status="active",
        project_id=project.id,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(task)
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


def test_tasks_group_and_project_catalog_routes(test_client, test_db):
    group = TaskGroup(
        user_id=TEST_USER_ID,
        title="Home",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(group)
    test_db.flush()
    project = TaskProject(
        user_id=TEST_USER_ID,
        title="Household",
        group_id=group.id,
        status="active",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(project)
    test_db.commit()

    groups_response = test_client.get("/api/v1/tasks/groups", headers=_auth_headers())
    assert groups_response.status_code == 200
    assert any(item["title"] == "Home" for item in groups_response.json())

    projects_response = test_client.get("/api/v1/tasks/projects", headers=_auth_headers())
    assert projects_response.status_code == 200
    assert any(item["title"] == "Household" for item in projects_response.json())


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


def test_tasks_apply_reopen_operation(test_client, test_db):
    task = Task(
        user_id=TEST_USER_ID,
        title="Completed task",
        status="completed",
        completed_at=datetime.now(UTC),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(task)
    test_db.commit()

    response = test_client.post(
        "/api/v1/tasks/apply",
        json={"op": "reopen", "id": str(task.id), "operation_id": "op-reopen-1"},
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["applied"] == ["op-reopen-1"]
    assert payload["tasks"][0]["status"] == "active"
    assert payload["tasks"][0]["deletedAt"] is None


def test_tasks_apply_reopen_operation_returns_removed_recurring_instance(
    test_client, test_db
):
    task = Task(
        user_id=TEST_USER_ID,
        title="Daily standup",
        status="completed",
        deadline=date(2026, 4, 18),
        repeating=True,
        repeat_template=True,
        recurrence_rule={"type": "daily", "interval": 1},
        next_instance_date=date(2026, 4, 19),
        completed_at=datetime.now(UTC),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(task)
    test_db.flush()
    task.repeat_template_id = task.id

    next_task = Task(
        user_id=TEST_USER_ID,
        title="Daily standup",
        status="active",
        deadline=date(2026, 4, 19),
        repeating=True,
        repeat_template=False,
        repeat_template_id=task.id,
        recurrence_rule={"type": "daily", "interval": 1},
        next_instance_date=date(2026, 4, 20),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(next_task)
    test_db.commit()

    response = test_client.post(
        "/api/v1/tasks/apply",
        json={"op": "reopen", "id": str(task.id), "operation_id": "op-reopen-2"},
        headers=_auth_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    returned_tasks = {item["id"]: item for item in payload["tasks"]}
    assert returned_tasks[str(task.id)]["status"] == "active"
    assert returned_tasks[str(task.id)]["deletedAt"] is None
    assert returned_tasks[str(next_task.id)]["status"] == "trashed"
    assert returned_tasks[str(next_task.id)]["deletedAt"] is not None


def test_today_tasks_snapshot_logs_background_failures(
    test_client, test_db, monkeypatch, caplog
):
    task = Task(
        user_id=TEST_USER_ID,
        title="Today task",
        status="active",
        deadline=date.today(),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(task)
    test_db.commit()

    def fail_snapshot(*_args, **_kwargs):
        raise RuntimeError("snapshot boom")

    monkeypatch.setattr(
        tasks_router.UserSettingsService,
        "update_tasks_snapshot",
        fail_snapshot,
    )
    caplog.set_level("ERROR", logger="api.routers.tasks")

    response = test_client.get("/api/v1/tasks/lists/today", headers=_auth_headers())

    assert response.status_code == 200
    assert "Snapshot update failed for user" in caplog.text


def test_tasks_sync_returns_updates(test_client, test_db):
    task = Task(
        user_id=TEST_USER_ID,
        title="Sync me",
        status="active",
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
