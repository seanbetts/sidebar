import uuid
from datetime import UTC, datetime

import pytest
from api.models.note import Note
from api.models.website import Website
from api.utils.metadata_helpers import get_max_pinned_order


@pytest.fixture
def db_session(test_db):
    return test_db


def _create_note(db_session, user_id: str, metadata: dict) -> Note:
    now = datetime.now(UTC)
    note = Note(
        user_id=user_id,
        title="Note",
        content="Body",
        metadata_=metadata,
        created_at=now,
        updated_at=now,
    )
    db_session.add(note)
    db_session.commit()
    db_session.refresh(note)
    return note


def _create_website(db_session, user_id: str, metadata: dict) -> Website:
    now = datetime.now(UTC)
    website = Website(
        user_id=user_id,
        url=f"https://example.com/{uuid.uuid4().hex}",
        domain="example.com",
        title="Example",
        content="Content",
        metadata_=metadata,
        created_at=now,
        updated_at=now,
    )
    db_session.add(website)
    db_session.commit()
    db_session.refresh(website)
    return website


def test_get_max_pinned_order_no_pinned(db_session):
    _create_note(db_session, "user-1", {"pinned": False})

    assert get_max_pinned_order(db_session, Note, "user-1") == -1


def test_get_max_pinned_order_uses_max(db_session):
    _create_note(db_session, "user-1", {"pinned": True, "pinned_order": 2})
    _create_note(db_session, "user-1", {"pinned": True, "pinned_order": 5})
    _create_note(db_session, "user-1", {"pinned": False, "pinned_order": 9})

    assert get_max_pinned_order(db_session, Note, "user-1") == 5


def test_get_max_pinned_order_ignores_invalid_values(db_session):
    _create_note(db_session, "user-1", {"pinned": True, "pinned_order": "bad"})
    _create_note(db_session, "user-1", {"pinned": True, "pinned_order": "4"})

    assert get_max_pinned_order(db_session, Note, "user-1") == 4


def test_get_max_pinned_order_for_websites(db_session):
    _create_website(db_session, "user-1", {"pinned": True, "pinned_order": 3})
    _create_website(db_session, "user-1", {"pinned": True, "pinned_order": 7})

    assert get_max_pinned_order(db_session, Website, "user-1") == 7
