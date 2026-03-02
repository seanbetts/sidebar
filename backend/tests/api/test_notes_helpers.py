from datetime import UTC, datetime
from types import SimpleNamespace

from api.services import notes_helpers


def _note() -> SimpleNamespace:
    timestamp = datetime(2025, 1, 1, tzinfo=UTC)
    return SimpleNamespace(
        id="note-1",
        user_id="user-1",
        title="Note",
        content="abc",
        plain_text="Body",
        content_format="rtf",
        folder_path="Work",
        pinned=True,
        pinned_order=2,
        is_folder_marker=False,
        updated_at=timestamp,
        created_at=timestamp,
        deleted_at=None,
        is_archived=False,
    )


def test_note_sync_payload_uses_explicit_note_columns():
    payload = notes_helpers.note_sync_payload(_note())

    assert payload["title"] == "Note"
    assert payload["plain_text"] == "Body"
    assert payload["content_format"] == "rtf"
    assert payload["folder"] == "Work"
    assert payload["pinned"] is True
    assert payload["pinned_order"] == 2
    assert payload["is_folder_marker"] is False
