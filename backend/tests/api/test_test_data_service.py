from datetime import UTC, date, datetime

import pytest
from api.models.conversation import Conversation
from api.models.task import Task
from api.models.task_group import TaskGroup
from api.models.task_project import TaskProject
from api.models.user_memory import UserMemory
from api.services.notes_service import NotesService
from api.services.test_data_service import TestDataService
from api.services.websites_service import WebsitesService
from sqlalchemy import or_


@pytest.fixture
def db_session(test_db):
    return test_db


def test_build_seed_plan_contains_seed_markers():
    plan = TestDataService.build_seed_plan("seed:test-data", now=datetime.now(UTC))

    assert plan.title_prefix.startswith("[seed:test-data]")
    assert any("seed:test-data" in (note.tags or []) for note in plan.notes)
    assert plan.scratchpad.startswith("# ")
    assert all(
        memory.path.startswith("memories/seed/seed:test-data")
        for memory in plan.memories
    )
    assert any(task.complete_on_seed for task in plan.tasks)
    assert any(task.status == "someday" for task in plan.tasks)
    assert any(conversation.archived for conversation in plan.conversations)


def test_seed_and_delete_round_trip(db_session):
    user_id = "test_user"
    plan = TestDataService.build_seed_plan("seed:test-data")

    seeded = TestDataService.seed_user_data(db_session, user_id, plan)
    assert seeded.notes > 0
    assert seeded.websites > 0
    assert seeded.conversations > 0
    assert seeded.tasks > 0

    notes = NotesService.list_notes(db_session, user_id)
    assert any(
        "seed:test-data" in (note.metadata_ or {}).get("tags", []) for note in notes
    )
    websites = WebsitesService.list_websites(db_session, user_id)
    assert any((site.title or "").startswith(plan.title_prefix) for site in websites)

    conversations = (
        db_session.query(Conversation)
        .filter(
            Conversation.user_id == user_id,
            Conversation.title.startswith(plan.title_prefix),
        )
        .all()
    )
    assert conversations

    memories = db_session.query(UserMemory).filter(UserMemory.user_id == user_id).all()
    assert memories

    tasks = (
        db_session.query(Task)
        .filter(
            Task.user_id == user_id,
            or_(
                Task.source_id == plan.seed_tag,
                Task.source_id.startswith(f"{plan.seed_tag}:"),
            ),
        )
        .all()
    )
    assert tasks
    assert all(task.source_id for task in tasks)
    assert len({task.source_id for task in tasks}) == len(tasks)
    assert any(task.status == "completed" and task.completed_at is not None for task in tasks)
    assert any(task.status == "someday" for task in tasks)
    assert any(
        task.status == "active" and task.deadline and task.deadline < date.today()
        for task in tasks
    )
    task_groups = (
        db_session.query(TaskGroup)
        .filter(
            TaskGroup.user_id == user_id,
            TaskGroup.deleted_at.is_(None),
            or_(
                TaskGroup.source_id == plan.seed_tag,
                TaskGroup.source_id.startswith(f"{plan.seed_tag}:"),
            ),
        )
        .all()
    )
    assert len(task_groups) == len(plan.task_groups)
    task_projects = (
        db_session.query(TaskProject)
        .filter(
            TaskProject.user_id == user_id,
            TaskProject.deleted_at.is_(None),
            or_(
                TaskProject.source_id == plan.seed_tag,
                TaskProject.source_id.startswith(f"{plan.seed_tag}:"),
            ),
        )
        .all()
    )
    assert len(task_projects) == len(plan.task_projects)

    archived_conversations = (
        db_session.query(Conversation)
        .filter(
            Conversation.user_id == user_id,
            Conversation.title.startswith(plan.title_prefix),
            Conversation.is_archived.is_(True),
        )
        .all()
    )
    assert archived_conversations

    deleted = TestDataService.delete_seed_data(db_session, user_id, plan)
    assert deleted.notes == seeded.notes + len(plan.folders)
    assert deleted.websites == seeded.websites
    assert deleted.conversations == seeded.conversations

    notes_after = NotesService.list_notes(db_session, user_id)
    assert all(
        "seed:test-data" not in (note.metadata_ or {}).get("tags", [])
        for note in notes_after
    )
    websites_after = WebsitesService.list_websites(db_session, user_id)
    assert all(
        not (site.title or "").startswith(plan.title_prefix) for site in websites_after
    )
    memories_after = (
        db_session.query(UserMemory)
        .filter(
            UserMemory.user_id == user_id,
            or_(
                UserMemory.path.startswith("memories/seed/seed:test-data"),
                UserMemory.path.startswith("/memories/seed/seed:test-data"),
            ),
        )
        .all()
    )
    assert not memories_after
    tasks_after = (
        db_session.query(Task)
        .filter(
            Task.user_id == user_id,
            or_(
                Task.source_id == plan.seed_tag,
                Task.source_id.startswith(f"{plan.seed_tag}:"),
            ),
            Task.deleted_at.is_(None),
        )
        .all()
    )
    assert not tasks_after

    reseeded = TestDataService.seed_user_data(db_session, user_id, plan)
    assert reseeded.notes > 0
    assert reseeded.websites == len(plan.websites)
