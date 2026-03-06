from datetime import UTC, datetime
from types import SimpleNamespace

from api.services.notes_document_types import note_document_from_plain_text
from api.services import notes_helpers


def _note() -> SimpleNamespace:
    timestamp = datetime(2025, 1, 1, tzinfo=UTC)
    return SimpleNamespace(
        id="note-1",
        user_id="user-1",
        title="Note",
        content="abc",
        document=note_document_from_plain_text("Body"),
        document_version=1,
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


def test_note_conflict_payload_uses_explicit_note_columns():
    payload = notes_helpers.note_conflict_payload(
        _note(),
        op="update",
        client_updated_at=datetime(2025, 1, 1, tzinfo=UTC),
    )
    server_note = payload["serverNote"]

    assert server_note["title"] == "Note"
    assert server_note["document"] == note_document_from_plain_text("Body")
    assert server_note["document_version"] == 1
    assert server_note["plain_text"] == "Body"
    assert server_note["folder"] == "Work"
    assert server_note["pinned"] is True
    assert server_note["pinned_order"] == 2
    assert server_note["is_folder_marker"] is False
