import uuid
from datetime import UTC, datetime

import pytest
from api.db.base import Base
from api.models.conversation import Conversation
from api.models.task import Task
from api.models.user_memory import UserMemory
from api.services.notes_service import NotesService
from api.services.test_data_service import TestDataService
from api.services.websites_service import WebsitesService
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


def test_build_seed_plan_contains_seed_markers():
    plan = TestDataService.build_seed_plan("seed:test-data", now=datetime.now(UTC))

    assert plan.title_prefix.startswith("[seed:test-data]")
    assert any("seed:test-data" in (note.tags or []) for note in plan.notes)
    assert plan.scratchpad.startswith("# ")
    assert all(
        memory.path.startswith("memories/seed/seed:test-data")
        for memory in plan.memories
    )


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

    memories = (
        db_session.query(UserMemory)
        .filter(UserMemory.user_id == user_id)
        .all()
    )
    assert memories

    tasks = (
        db_session.query(Task)
        .filter(Task.user_id == user_id, Task.source_id == plan.seed_tag)
        .all()
    )
    assert tasks

    deleted = TestDataService.delete_seed_data(db_session, user_id, plan)
    assert deleted.notes == seeded.notes
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
            UserMemory.path.startswith("/memories/seed/seed:test-data"),
        )
        .all()
    )
    assert not memories_after
    tasks_after = (
        db_session.query(Task)
        .filter(
            Task.user_id == user_id,
            Task.source_id == plan.seed_tag,
            Task.deleted_at.is_(None),
        )
        .all()
    )
    assert not tasks_after
