from datetime import UTC, datetime, timedelta

import pytest

from api.services.agent.tools.skills_guard import SkillsGuardService
from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_service import NotesService


@pytest.fixture
def db_session(test_db):
    return test_db


def test_create_confirmation_for_destructive_tool_stores_pending_decision() -> None:
    service = SkillsGuardService(now=lambda: datetime(2026, 5, 9, tzinfo=UTC))

    event = service.create_confirmation_requested_event(
        user_id="user-1",
        tool_call_id="tool-1",
        tool_name="Delete_Note",
        display_name="Delete Note",
        parameters={"note_id": "note-1"},
        skill_id="notes",
        icon_key="notes",
    )

    assert event["type"] == "tool_confirmation_requested"
    data = event["data"]
    assert data["tool_call_id"] == "tool-1"
    assert data["tool_name"] == "Delete Note"
    assert data["parameters"] == {"note_id": "note-1"}
    assert data["summary"] == "Delete note note-1?"
    assert data["undo_supported"] is True
    assert data["expires_at"] == "2026-05-09T00:05:00+00:00"

    pending = service.resolve_confirmation(
        data["confirmation_id"],
        user_id="user-1",
        decision="decline",
    )
    assert pending.tool_name == "Delete_Note"
    assert pending.display_name == "Delete Note"
    assert pending.parameters == {"note_id": "note-1"}


def test_confirmation_decision_is_single_use() -> None:
    service = SkillsGuardService(now=lambda: datetime(2026, 5, 9, tzinfo=UTC))
    event = service.create_confirmation_requested_event(
        user_id="user-1",
        tool_call_id="tool-1",
        tool_name="Delete_Note",
        display_name="Delete Note",
        parameters={"note_id": "note-1"},
    )
    confirmation_id = event["data"]["confirmation_id"]

    service.resolve_confirmation(
        confirmation_id,
        user_id="user-1",
        decision="decline",
    )

    with pytest.raises(ValueError, match="already resolved"):
        service.resolve_confirmation(
            confirmation_id,
            user_id="user-1",
            decision="accept",
        )


def test_undo_token_restores_deleted_note_once(db_session) -> None:
    note = NotesService.create_note(
        db_session,
        "user-1",
        note_document_from_plain_text("# Undo\n\nBody"),
    )
    NotesService.soft_delete_note(db_session, "user-1", note.id)
    db_session.commit()
    service = SkillsGuardService(now=lambda: datetime(2026, 5, 9, tzinfo=UTC))
    event = service.create_undo_available_event(
        user_id="user-1",
        display_name="Delete Note",
        parameters={"note_id": str(note.id)},
        result_data={"id": str(note.id)},
    )

    assert event is not None
    assert event["type"] == "undo_available"
    assert event["data"]["entity_type"] == "note"
    assert event["data"]["entity_id"] == str(note.id)

    restored = service.consume_undo_token(
        event["data"]["undo_token"],
        user_id="user-1",
        db=db_session,
    )
    assert restored["entity_type"] == "note"
    assert restored["entity_id"] == str(note.id)
    assert NotesService.get_note(db_session, "user-1", note.id) is not None

    with pytest.raises(ValueError, match="already used"):
        service.consume_undo_token(
            event["data"]["undo_token"],
            user_id="user-1",
            db=db_session,
        )


def test_expired_undo_token_is_rejected(db_session) -> None:
    now = datetime(2026, 5, 9, tzinfo=UTC)
    service = SkillsGuardService(now=lambda: now)
    event = service.create_undo_available_event(
        user_id="user-1",
        display_name="Delete Note",
        parameters={"note_id": "note-1"},
        result_data={"id": "note-1"},
    )
    assert event is not None

    expired_service = SkillsGuardService(
        now=lambda: now + timedelta(minutes=6),
        pending_confirmations=service.pending_confirmations,
        undo_tokens=service.undo_tokens,
    )
    with pytest.raises(ValueError, match="expired"):
        expired_service.consume_undo_token(
            event["data"]["undo_token"],
            user_id="user-1",
            db=db_session,
        )
