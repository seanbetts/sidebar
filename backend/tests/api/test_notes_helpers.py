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
        metadata_={"plain_text": "Body", "content_format": "rtf"},
        updated_at=timestamp,
        created_at=timestamp,
        deleted_at=None,
        is_archived=False,
    )


def test_note_sync_payload_runs_canonicality_diagnostics(monkeypatch):
    captured: dict[str, object] = {}

    def _fake_diagnose(**kwargs):
        captured.update(kwargs)
        return []

    monkeypatch.setattr(
        notes_helpers,
        "diagnose_note_read_canonicality",
        _fake_diagnose,
    )

    payload = notes_helpers.note_sync_payload(_note())

    assert payload["plain_text"] == "Body"
    assert payload["content_format"] == "rtf"
    assert captured["context"] == "notes_helpers.note_sync_payload"
    assert captured["note_id"] == "note-1"
    assert captured["require_content"] is True
