from datetime import UTC, datetime, timedelta

import pytest
from api.exceptions import ConflictError
from api.services.notes_document_types import note_document_from_plain_text
from api.schemas.filters import NoteFilters
from api.services.notes_service import NotesService
from api.services.notes_write_contract import is_canonical_base64_rtf


@pytest.fixture
def db_session(test_db):
    return test_db


def _document(plain_text: str) -> dict[str, object]:
    return note_document_from_plain_text(plain_text)


def test_create_and_read_note(db_session):
    content = "# Test Note\n\nBody"
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document(content),
        folder="Work",
    )

    assert note.title == "Test Note"
    fetched = NotesService.get_note(db_session, "test_user", note.id, mark_opened=True)
    assert fetched is not None
    assert fetched.title == "Test Note"
    assert fetched.document == _document(content)
    assert fetched.document_version == 1
    assert is_canonical_base64_rtf(fetched.content) is True
    assert fetched.plain_text == content
    assert fetched.content_format == "rtf"
    assert fetched.last_opened_at is not None


def test_update_note_title(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Old Title\n\nBody"),
    )
    updated = NotesService.update_note(
        db_session,
        "test_user",
        note.id,
        _document("# New Title\n\nBody"),
    )

    assert updated.title == "New Title"
    assert updated.document == _document("# New Title\n\nBody")
    assert updated.document_version == 1
    assert is_canonical_base64_rtf(updated.content) is True
    assert updated.plain_text == "# New Title\n\nBody"


def test_update_folder_and_pinned(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Folder Note\n\nBody"),
    )
    moved = NotesService.update_folder(
        db_session, "test_user", note.id, "Projects/Alpha"
    )
    pinned = NotesService.update_pinned(db_session, "test_user", note.id, True)

    assert moved.folder_path == "Projects/Alpha"
    assert pinned.pinned is True


def test_update_pinned_assigns_next_order(db_session):
    note_a = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Alpha\n\nBody"),
    )
    note_b = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Beta\n\nBody"),
    )

    pinned_a = NotesService.update_pinned(db_session, "test_user", note_a.id, True)
    pinned_b = NotesService.update_pinned(db_session, "test_user", note_b.id, True)

    assert pinned_a.pinned_order == 0
    assert pinned_b.pinned_order == 1


def test_update_folder_can_clear_pinned_state(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Move Me\n\nBody"),
    )
    NotesService.update_pinned(db_session, "test_user", note.id, True)

    moved = NotesService.update_folder(
        db_session,
        "test_user",
        note.id,
        "Projects/Beta",
        clear_pinned=True,
    )

    assert moved.folder_path == "Projects/Beta"
    assert moved.pinned is False
    assert moved.pinned_order is None


def test_list_notes_filters(db_session):
    now = datetime.now(UTC)
    earlier = now - timedelta(days=2)

    note_a = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Alpha\n\nBody"),
        folder="Work",
    )
    note_b = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Beta\n\nBody"),
        folder="Archive/Old",
    )
    NotesService.update_pinned(db_session, "test_user", note_a.id, True)

    note_a.created_at = earlier
    note_a.updated_at = earlier
    note_b.created_at = now
    note_b.updated_at = now
    db_session.commit()

    pinned_notes = NotesService.list_notes(
        db_session, "test_user", NoteFilters(pinned=True)
    )
    assert any(n.id == note_a.id for n in pinned_notes)

    archived_notes = NotesService.list_notes(
        db_session, "test_user", NoteFilters(archived=True)
    )
    assert any(n.id == note_b.id for n in archived_notes)

    active_notes = NotesService.list_notes(
        db_session, "test_user", NoteFilters(archived=False)
    )
    assert all(n.id != note_b.id for n in active_notes)

    filtered = NotesService.list_notes(
        db_session, "test_user", NoteFilters(folder="Work", title_search="Alpha")
    )
    assert len(filtered) == 1
    assert filtered[0].id == note_a.id


def test_archived_summary(db_session):
    now = datetime.now(UTC)
    archived_at = now - timedelta(hours=2)

    archived_note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Archived\n\nBody"),
        folder="Archive/Old",
    )
    NotesService.create_note(
        db_session,
        "test_user",
        _document("# Active\n\nBody"),
        folder="Work",
    )

    archived_note.updated_at = archived_at
    db_session.commit()

    summary = NotesService.archived_summary(db_session, "test_user")

    assert summary["archived_count"] == 1
    assert summary["archived_last_updated"] is not None
    summary_ts = datetime.fromisoformat(summary["archived_last_updated"])
    assert summary_ts.astimezone(UTC) == archived_at


def test_soft_delete_note_clears_pinned_state(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Delete Me\n\nBody"),
    )
    NotesService.update_pinned(db_session, "test_user", note.id, True)

    deleted = NotesService.soft_delete_note(db_session, "test_user", note.id)

    assert deleted is not None
    assert deleted.deleted_at is not None
    assert deleted.pinned is False
    assert deleted.pinned_order is None


def test_update_note_conflict(db_session):
    note = NotesService.create_note(
        db_session,
        "test_user",
        _document("# Title\n\nBody"),
    )
    stale = note.updated_at - timedelta(seconds=10)

    with pytest.raises(ConflictError):
        NotesService.update_note(
            db_session,
            "test_user",
            note.id,
            _document("# Title\n\nUpdated"),
            client_updated_at=stale,
        )
