from datetime import UTC, datetime, timedelta

import pytest
from api.exceptions import ConflictError
from api.schemas.filters import NoteFilters
from api.services.notes_content_codec import canonical_note_content_from_plain_text
from api.services.notes_service import NotesService
from api.services.notes_write_contract import is_canonical_base64_rtf


@pytest.fixture
def db_session(test_db):
    return test_db


def _canonical_pair(plain_text: str) -> tuple[str, str]:
    canonical = canonical_note_content_from_plain_text(plain_text)
    return canonical.content, canonical.plain_text


def test_create_and_read_note(db_session):
    content = "# Test Note\n\nBody"
    canonical_content, canonical_plain_text = _canonical_pair(content)
    note = NotesService.create_note(
        db_session,
        "test_user",
        canonical_content,
        plain_text=canonical_plain_text,
        title="Test Note",
        folder="Work",
    )

    assert note.title == "Test Note"
    fetched = NotesService.get_note(db_session, "test_user", note.id, mark_opened=True)
    assert fetched is not None
    assert fetched.title == "Test Note"
    assert is_canonical_base64_rtf(fetched.content) is True
    assert (fetched.metadata_ or {}).get("plain_text") == content
    assert (fetched.metadata_ or {}).get("content_format") == "rtf"
    assert fetched.last_opened_at is not None


def test_update_note_title(db_session):
    original_content, original_plain_text = _canonical_pair("# Old Title\n\nBody")
    note = NotesService.create_note(
        db_session,
        "test_user",
        original_content,
        plain_text=original_plain_text,
        title="Old Title",
    )
    updated_content, updated_plain_text = _canonical_pair("# New Title\n\nBody")
    updated = NotesService.update_note(
        db_session,
        "test_user",
        note.id,
        updated_content,
        plain_text=updated_plain_text,
        title="New Title",
    )

    assert updated.title == "New Title"
    assert is_canonical_base64_rtf(updated.content) is True
    assert (updated.metadata_ or {}).get("plain_text") == "# New Title\n\nBody"


def test_update_folder_and_pinned(db_session):
    content, plain_text = _canonical_pair("# Folder Note\n\nBody")
    note = NotesService.create_note(
        db_session,
        "test_user",
        content,
        plain_text=plain_text,
    )
    moved = NotesService.update_folder(
        db_session, "test_user", note.id, "Projects/Alpha"
    )
    pinned = NotesService.update_pinned(db_session, "test_user", note.id, True)

    assert (moved.metadata_ or {}).get("folder") == "Projects/Alpha"
    assert (pinned.metadata_ or {}).get("pinned") is True


def test_update_pinned_assigns_next_order(db_session):
    content_a, plain_text_a = _canonical_pair("# Alpha\n\nBody")
    content_b, plain_text_b = _canonical_pair("# Beta\n\nBody")
    note_a = NotesService.create_note(
        db_session,
        "test_user",
        content_a,
        plain_text=plain_text_a,
    )
    note_b = NotesService.create_note(
        db_session,
        "test_user",
        content_b,
        plain_text=plain_text_b,
    )

    pinned_a = NotesService.update_pinned(db_session, "test_user", note_a.id, True)
    pinned_b = NotesService.update_pinned(db_session, "test_user", note_b.id, True)

    assert (pinned_a.metadata_ or {}).get("pinned_order") == 0
    assert (pinned_b.metadata_ or {}).get("pinned_order") == 1


def test_update_folder_can_clear_pinned_state(db_session):
    content, plain_text = _canonical_pair("# Move Me\n\nBody")
    note = NotesService.create_note(
        db_session,
        "test_user",
        content,
        plain_text=plain_text,
    )
    NotesService.update_pinned(db_session, "test_user", note.id, True)

    moved = NotesService.update_folder(
        db_session,
        "test_user",
        note.id,
        "Projects/Beta",
        clear_pinned=True,
    )

    metadata = moved.metadata_ or {}
    assert metadata.get("folder") == "Projects/Beta"
    assert metadata.get("pinned") is False
    assert metadata.get("pinned_order") is None


def test_list_notes_filters(db_session):
    now = datetime.now(UTC)
    earlier = now - timedelta(days=2)

    content_a, plain_text_a = _canonical_pair("# Alpha\n\nBody")
    content_b, plain_text_b = _canonical_pair("# Beta\n\nBody")
    note_a = NotesService.create_note(
        db_session,
        "test_user",
        content_a,
        plain_text=plain_text_a,
        title="Alpha",
        folder="Work",
    )
    note_b = NotesService.create_note(
        db_session,
        "test_user",
        content_b,
        plain_text=plain_text_b,
        title="Beta",
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

    archived_content, archived_plain_text = _canonical_pair("# Archived\n\nBody")
    archived_note = NotesService.create_note(
        db_session,
        "test_user",
        archived_content,
        plain_text=archived_plain_text,
        folder="Archive/Old",
    )
    active_content, active_plain_text = _canonical_pair("# Active\n\nBody")
    NotesService.create_note(
        db_session,
        "test_user",
        active_content,
        plain_text=active_plain_text,
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
    content, plain_text = _canonical_pair("# Delete Me\n\nBody")
    note = NotesService.create_note(
        db_session,
        "test_user",
        content,
        plain_text=plain_text,
    )
    NotesService.update_pinned(db_session, "test_user", note.id, True)

    deleted = NotesService.soft_delete_note(db_session, "test_user", note.id)

    assert deleted is not None
    assert deleted.deleted_at is not None
    metadata = deleted.metadata_ or {}
    assert metadata.get("pinned") is False
    assert metadata.get("pinned_order") is None


def test_update_note_conflict(db_session):
    original_content, original_plain_text = _canonical_pair("# Title\n\nBody")
    note = NotesService.create_note(
        db_session,
        "test_user",
        original_content,
        plain_text=original_plain_text,
    )
    stale = note.updated_at - timedelta(seconds=10)
    updated_content, updated_plain_text = _canonical_pair("# Title\n\nUpdated")

    with pytest.raises(ConflictError):
        NotesService.update_note(
            db_session,
            "test_user",
            note.id,
            updated_content,
            plain_text=updated_plain_text,
            client_updated_at=stale,
        )
