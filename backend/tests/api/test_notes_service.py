import os
import uuid
from datetime import datetime, timezone, timedelta

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from api.db.base import Base
from api.services.notes_service import NotesService


@pytest.fixture
def db_session():
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        pytest.skip("DATABASE_URL not set")

    engine = create_engine(database_url)
    connection = engine.connect().execution_options(isolation_level="AUTOCOMMIT")
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
        engine.dispose()


def test_create_and_read_note(db_session):
    content = "# Test Note\n\nBody"
    note = NotesService.create_note(db_session, content, folder="Work")

    assert note.title == "Test Note"
    fetched = NotesService.get_note(db_session, note.id, mark_opened=True)
    assert fetched is not None
    assert fetched.title == "Test Note"
    assert fetched.content == content
    assert fetched.last_opened_at is not None


def test_update_note_title(db_session):
    note = NotesService.create_note(db_session, "# Old Title\n\nBody")
    updated = NotesService.update_note(db_session, note.id, "# New Title\n\nBody")

    assert updated.title == "New Title"
    assert "New Title" in updated.content


def test_update_folder_and_pinned(db_session):
    note = NotesService.create_note(db_session, "# Folder Note\n\nBody")
    moved = NotesService.update_folder(db_session, note.id, "Projects/Alpha")
    pinned = NotesService.update_pinned(db_session, note.id, True)

    assert (moved.metadata_ or {}).get("folder") == "Projects/Alpha"
    assert (pinned.metadata_ or {}).get("pinned") is True


def test_list_notes_filters(db_session):
    now = datetime.now(timezone.utc)
    earlier = now - timedelta(days=2)

    note_a = NotesService.create_note(db_session, "# Alpha\n\nBody", folder="Work")
    note_b = NotesService.create_note(db_session, "# Beta\n\nBody", folder="Archive/Old")
    NotesService.update_pinned(db_session, note_a.id, True)

    note_a.created_at = earlier
    note_a.updated_at = earlier
    note_b.created_at = now
    note_b.updated_at = now
    db_session.commit()

    pinned_notes = NotesService.list_notes(db_session, pinned=True)
    assert any(n.id == note_a.id for n in pinned_notes)

    archived_notes = NotesService.list_notes(db_session, archived=True)
    assert any(n.id == note_b.id for n in archived_notes)

    active_notes = NotesService.list_notes(db_session, archived=False)
    assert all(n.id != note_b.id for n in active_notes)

    filtered = NotesService.list_notes(db_session, folder="Work", title_search="Alpha")
    assert len(filtered) == 1
    assert filtered[0].id == note_a.id
