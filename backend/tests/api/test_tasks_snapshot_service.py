from datetime import UTC, datetime

from api.services.tasks_snapshot_service import TasksSnapshotService


def test_build_snapshot_uses_markdown_headings_and_sections() -> None:
    now = datetime(2026, 3, 1, 9, 0, tzinfo=UTC)
    today_tasks = [
        {
            "id": "task-overdue",
            "title": "Pay rent",
            "deadline": "2026-02-28",
            "notes": "Check bank transfer reference.",
            "groupId": "group-home",
            "projectId": "project-admin",
        },
        {
            "id": "task-today",
            "title": "Ship iOS build",
            "deadline": "2026-03-01",
            "notes": "",
            "groupId": "group-work",
            "projectId": "project-app",
        },
    ]
    tomorrow_tasks = [
        {
            "id": "task-tomorrow",
            "title": "Review PR queue",
            "deadline": "2026-03-02",
            "notes": "",
            "groupId": "group-work",
            "projectId": "project-app",
        }
    ]
    completed_today = [
        {
            "id": "task-complete",
            "title": "Clear inbox",
            "deadline": "2026-03-01",
            "notes": "",
            "groupId": "group-work",
            "projectId": "project-admin",
        }
    ]
    groups = [
        {"id": "group-home", "title": "Home"},
        {"id": "group-work", "title": "Work"},
    ]
    projects = [
        {"id": "project-admin", "title": "Admin"},
        {"id": "project-app", "title": "App"},
    ]

    snapshot = TasksSnapshotService.build_snapshot(
        today_tasks=today_tasks,
        tomorrow_tasks=tomorrow_tasks,
        completed_today=completed_today,
        groups=groups,
        projects=projects,
        now=now,
    )

    assert "### Overdue" in snapshot
    assert "### Today" in snapshot
    assert "### Tomorrow" in snapshot
    assert "### Completed today" in snapshot
    assert "- [ ] Pay rent (Home, Admin, overdue 1 day)" in snapshot
    assert "- [ ] Ship iOS build (Work, App)" in snapshot
    assert "- [x] Clear inbox (Work, Admin)" in snapshot
    assert "  - Notes: Check bank transfer reference." in snapshot


def test_build_snapshot_omits_overdue_heading_when_not_needed() -> None:
    now = datetime(2026, 3, 1, 9, 0, tzinfo=UTC)
    snapshot = TasksSnapshotService.build_snapshot(
        today_tasks=[],
        tomorrow_tasks=[],
        completed_today=[],
        groups=[],
        projects=[],
        now=now,
    )

    assert "### Overdue" not in snapshot
    assert "### Today" in snapshot
    assert "### Tomorrow" in snapshot
    assert "### Completed today" in snapshot
    assert snapshot.count("- [ ] None") == 3
