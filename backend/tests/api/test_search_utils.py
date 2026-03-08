"""Tests for search utility helpers."""

from datetime import UTC, datetime

from api.models.note import Note
from api.services.notes_document_types import note_document_from_plain_text
from api.utils.search import build_text_search_filter


def _create_note(test_db, user_id: str, title: str) -> Note:
    now = datetime.now(UTC)
    note = Note(
        user_id=user_id,
        title=title,
        document=note_document_from_plain_text("Body"),
        document_version=1,
        plain_text="Body",
        folder_path="",
        pinned=False,
        pinned_order=None,
        is_folder_marker=False,
        is_archived=False,
        metadata_={},
        created_at=now,
        updated_at=now,
        last_opened_at=None,
        deleted_at=None,
    )
    test_db.add(note)
    test_db.commit()
    test_db.refresh(note)
    return note


def test_build_text_search_filter_case_insensitive(test_db):
    _create_note(test_db, "user-1", "Alpha")
    _create_note(test_db, "user-1", "Beta")

    search_filter = build_text_search_filter([Note.title], "alpha")
    results = test_db.query(Note).filter(Note.user_id == "user-1", search_filter).all()

    assert [note.title for note in results] == ["Alpha"]


def test_build_text_search_filter_case_sensitive(test_db):
    _create_note(test_db, "user-1", "Alpha")
    _create_note(test_db, "user-1", "alpha")

    search_filter = build_text_search_filter([Note.title], "Alpha", case_sensitive=True)
    results = test_db.query(Note).filter(Note.user_id == "user-1", search_filter).all()

    assert {note.title for note in results} == {"Alpha"}
