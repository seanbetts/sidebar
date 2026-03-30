import uuid
from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from api.services import notes_workspace_service as service_module
from api.services.notes_document_types import (
    NOTE_DOCUMENT_VERSION,
    note_document_from_plain_text,
    validate_note_document,
)
from api.services.notes_workspace_service import NotesWorkspaceService
from api.models.note import Note
from sqlalchemy import inspect
from sqlalchemy.orm.attributes import NO_VALUE


class FakeQuery:
    def __init__(self, results):
        self._results = list(results)
        self._limit = None

    def options(self, *_, **__):
        return self

    def filter(self, *_, **__):
        return self

    def order_by(self, *_, **__):
        return self

    def limit(self, limit):
        self._limit = limit
        return self

    def all(self):
        if self._limit is None:
            return list(self._results)
        return list(self._results)[: self._limit]


class FakeDB:
    def __init__(self, notes):
        self._notes = notes
        self.added = []
        self.commits = 0

    def query(self, *_):
        return FakeQuery(self._notes)

    def add(self, note):
        self.added.append(note)

    def commit(self):
        self.commits += 1


def _note(title="Title", content="Body", folder="", pinned=False):
    is_archived = folder == "Archive" or folder.startswith("Archive/")
    timestamp = datetime(2024, 1, 1, tzinfo=UTC)
    return SimpleNamespace(
        id="note-1",
        user_id="user-1",
        title=title,
        content="",
        document=note_document_from_plain_text(content),
        document_version=NOTE_DOCUMENT_VERSION,
        plain_text=content,
        content_format="rtf",
        folder_path=folder,
        pinned=pinned,
        pinned_order=0 if pinned else None,
        is_folder_marker=False,
        updated_at=timestamp,
        created_at=timestamp,
        deleted_at=None,
        is_archived=is_archived,
    )


def test_list_tree_uses_notes_service(monkeypatch):
    db = FakeDB([_note()])
    monkeypatch.setattr(
        service_module, "build_notes_tree", lambda notes: {"children": notes}
    )

    result = NotesWorkspaceService.list_tree(db, "user-1")
    assert result["children"]


def test_search_returns_items():
    db = FakeDB([_note(title="Alpha", folder="Inbox", pinned=True)])
    result = NotesWorkspaceService.search(db, "user-1", "Alpha", limit=10)
    assert result["items"][0]["name"] == "Alpha"
    assert result["items"][0]["pinned"] is True


def test_search_excludes_legacy_scratchpad_items(test_db):
    legacy = Note(
        id=uuid.uuid4(),
        user_id="user-1",
        title="# ✏️ Scratchpad",
        document=note_document_from_plain_text("# ✏️ Scratchpad\n\nBody"),
        document_version=NOTE_DOCUMENT_VERSION,
        plain_text="# ✏️ Scratchpad\n\nBody",
        folder_path="",
        pinned=False,
        pinned_order=None,
        is_folder_marker=False,
        is_archived=False,
    )
    visible = Note(
        id=uuid.uuid4(),
        user_id="user-1",
        title="Visible Note",
        document=note_document_from_plain_text("Visible Note\nScratchpad body"),
        document_version=NOTE_DOCUMENT_VERSION,
        plain_text="Visible Note\nScratchpad body",
        folder_path="",
        pinned=False,
        pinned_order=None,
        is_folder_marker=False,
        is_archived=False,
    )
    test_db.add_all([legacy, visible])
    test_db.commit()

    result = NotesWorkspaceService.search(test_db, "user-1", "Scratchpad", limit=10)

    names = [item["name"] for item in result["items"]]
    assert "# ✏️ Scratchpad" not in names
    assert "Visible Note" in names


def test_build_note_payload_includes_explicit_state_fields():
    note = _note(title="Alpha", content="Body", folder="Inbox", pinned=True)
    payload = NotesWorkspaceService.build_note_payload(note, include_content=True)
    assert payload["title"] == "Alpha"
    assert payload["name"] == "Alpha"
    assert payload["document"] == note_document_from_plain_text("Body")
    assert payload["document_version"] == NOTE_DOCUMENT_VERSION
    assert payload["plain_text"] == "Body"
    assert payload["folder"] == "Inbox"
    assert payload["pinned"] is True
    assert payload["archived"] is False
    assert payload["is_folder_marker"] is False


def test_create_note_fallback_uses_block_zero_title_semantics(monkeypatch):
    timestamp = datetime(2024, 1, 1, tzinfo=UTC)
    created = SimpleNamespace(
        _snapshot_id="note-1",
        _snapshot_updated_at=timestamp,
    )
    document = {
        "version": 1,
        "blocks": [
            {"type": "title", "content": [{"text": "   ", "marks": []}]},
            {"type": "paragraph", "content": [{"text": "Body title", "marks": []}]},
        ],
    }

    monkeypatch.setattr(
        service_module.NotesService,
        "create_note",
        lambda *args, **kwargs: created,
    )

    def raise_deleted(*args, **kwargs):
        raise service_module.ObjectDeletedError(None)

    monkeypatch.setattr(NotesWorkspaceService, "build_note_payload", raise_deleted)

    result = NotesWorkspaceService.create_note(FakeDB([]), "user-1", document)

    assert result["title"] == "New Note"
    assert result["name"] == "New Note"
    assert result["plain_text"] == "   \nBody title"
    assert result["document"] == validate_note_document(document)
    assert result["document_version"] == NOTE_DOCUMENT_VERSION


def test_create_note_fallback_normalizes_block_zero_to_title(monkeypatch):
    timestamp = datetime(2024, 1, 1, tzinfo=UTC)
    created = SimpleNamespace(
        _snapshot_id="note-1",
        _snapshot_updated_at=timestamp,
    )
    document = {
        "version": 1,
        "blocks": [
            {"type": "heading", "content": [{"text": "Semantic Heading", "marks": []}]},
            {"type": "paragraph", "content": [{"text": "Body line", "marks": []}]},
        ],
    }

    monkeypatch.setattr(
        service_module.NotesService,
        "create_note",
        lambda *args, **kwargs: created,
    )

    def raise_deleted(*args, **kwargs):
        raise service_module.ObjectDeletedError(None)

    monkeypatch.setattr(NotesWorkspaceService, "build_note_payload", raise_deleted)

    result = NotesWorkspaceService.create_note(FakeDB([]), "user-1", document)

    assert result["title"] == "Semantic Heading"
    assert result["name"] == "Semantic Heading"
    assert result["plain_text"] == "Semantic Heading\nBody line"
    assert result["document_version"] == NOTE_DOCUMENT_VERSION
    assert result["document"]["blocks"][0]["type"] == "title"


def test_create_folder_returns_exists_when_present():
    db = FakeDB([_note(folder="Projects/2025")])
    result = NotesWorkspaceService.create_folder(db, "user-1", "Projects")
    assert result == {"success": True, "exists": True}
    assert db.added == []


def test_rename_folder_updates_notes(monkeypatch):
    note = _note(folder="Old/Child")
    db = FakeDB([note])

    result = NotesWorkspaceService.rename_folder(db, "user-1", "Old", "New")
    assert result["newPath"] == "folder:New"
    assert note.folder_path == "New/Child"
    assert db.commits == 1


def test_move_folder_rejects_invalid_destination():
    db = FakeDB([_note(folder="Old/Child")])
    with pytest.raises(ValueError):
        NotesWorkspaceService.move_folder(db, "user-1", "Old", "Old/Sub")


def test_list_tree_query_defers_note_content_columns(test_db):
    note = Note(
        id=uuid.uuid4(),
        user_id="user-1",
        title="Heavy note",
        document=note_document_from_plain_text("Body"),
        document_version=NOTE_DOCUMENT_VERSION,
        plain_text="Body",
        folder_path="",
        pinned=False,
        pinned_order=None,
        is_folder_marker=False,
        is_archived=False,
    )
    test_db.add(note)
    test_db.commit()
    test_db.expire_all()

    listed = NotesWorkspaceService._query_items(
        test_db,
        "user-1",
        include_archived=False,
    )[0]

    assert inspect(listed).attrs.document.loaded_value is NO_VALUE
    assert inspect(listed).attrs.plain_text.loaded_value is NO_VALUE


def test_get_note_rejects_legacy_scratchpad_title(monkeypatch):
    legacy_scratchpad = _note(title="# ✏️ Scratchpad", content="# ✏️ Scratchpad\n\nBody")
    monkeypatch.setattr(
        service_module.NotesService,
        "get_note",
        lambda *args, **kwargs: legacy_scratchpad,
    )

    with pytest.raises(service_module.NoteNotFoundError, match="Note not found"):
        NotesWorkspaceService.get_note(FakeDB([]), "user-1", str(uuid.uuid4()))
