from datetime import UTC, datetime
from types import SimpleNamespace

import pytest
from api.services import notes_workspace_service as service_module
from api.services.notes_workspace_service import NotesWorkspaceService


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
        content=content,
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


def test_build_note_payload_includes_explicit_state_fields():
    note = _note(title="Alpha", content="Body", folder="Inbox", pinned=True)
    payload = NotesWorkspaceService.build_note_payload(note, include_content=True)
    assert payload["title"] == "Alpha"
    assert payload["name"] == "Alpha"
    assert payload["plain_text"] == "Body"
    assert payload["content_format"] == "rtf"
    assert payload["folder"] == "Inbox"
    assert payload["pinned"] is True
    assert payload["archived"] is False
    assert payload["is_folder_marker"] is False


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
