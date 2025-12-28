from datetime import datetime, timezone
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from api.services import files_workspace_service as service_module
from api.services.files_workspace_service import FilesWorkspaceService


class DummyStorage:
    def __init__(self):
        self.calls = []

    def move_object(self, src, dst):
        self.calls.append(("move", src, dst))

    def delete_object(self, key):
        self.calls.append(("delete", key))

    def get_object(self, key):
        self.calls.append(("get", key))
        return b"hello"

    def put_object(self, key, data, content_type=None):
        self.calls.append(("put", key, data, content_type))


class DummyDB:
    def __init__(self):
        self.commits = 0

    def commit(self):
        self.commits += 1


def _record(path, category="file", bucket_key="bucket/key", content_type="text/plain"):
    return SimpleNamespace(
        path=path,
        category=category,
        bucket_key=bucket_key,
        size=1,
        content_type=content_type,
        updated_at=datetime(2024, 1, 1, tzinfo=timezone.utc),
    )


def test_create_folder_calls_upsert(monkeypatch):
    calls = {}
    dummy_storage = DummyStorage()

    def fake_upsert(db, user_id, path, **kwargs):
        calls["path"] = path
        calls["bucket_key"] = kwargs["bucket_key"]
        calls["category"] = kwargs["category"]
        return _record(path, category="folder", bucket_key=kwargs["bucket_key"])

    monkeypatch.setattr(service_module, "storage_backend", dummy_storage)
    monkeypatch.setattr(service_module.FilesService, "upsert_file", fake_upsert)

    result = FilesWorkspaceService.create_folder(DummyDB(), "user-1", "base", "folder")
    assert result["success"] is True
    assert calls["path"] == "base/folder"
    assert calls["bucket_key"] == "user-1/base/folder/"
    assert calls["category"] == "folder"


def test_rename_file_moves_object(monkeypatch):
    dummy_storage = DummyStorage()
    db = DummyDB()
    record = _record("base/old.txt", bucket_key="user-1/base/old.txt")

    monkeypatch.setattr(service_module, "storage_backend", dummy_storage)
    monkeypatch.setattr(service_module.FilesService, "get_by_path", lambda *_: record)
    monkeypatch.setattr(service_module.FilesService, "list_by_prefix", lambda *_: [])

    result = FilesWorkspaceService.rename(db, "user-1", "base", "old.txt", "new.txt")
    assert result["success"] is True
    assert result["newPath"] == "new.txt"
    assert record.path == "base/new.txt"
    assert record.bucket_key == "user-1/base/new.txt"
    assert db.commits == 1
    assert dummy_storage.calls[0] == ("move", "user-1/base/old.txt", "user-1/base/new.txt")


def test_delete_file_marks_deleted(monkeypatch):
    dummy_storage = DummyStorage()
    record = _record("base/file.txt", bucket_key="user-1/base/file.txt")

    monkeypatch.setattr(service_module, "storage_backend", dummy_storage)
    monkeypatch.setattr(service_module.FilesService, "get_by_path", lambda *_: record)
    monkeypatch.setattr(service_module.FilesService, "mark_deleted", lambda *_: None)

    result = FilesWorkspaceService.delete(DummyDB(), "user-1", "base", "file.txt")
    assert result["success"] is True
    assert dummy_storage.calls[0] == ("delete", "user-1/base/file.txt")


def test_get_content_rejects_non_text(monkeypatch):
    dummy_storage = DummyStorage()
    dummy_storage.get_object = lambda _: b"\xff\xfe\xfd"
    record = _record("base/file.bin", content_type="application/octet-stream")

    monkeypatch.setattr(service_module, "storage_backend", dummy_storage)
    monkeypatch.setattr(service_module.FilesService, "get_by_path", lambda *_: record)

    with pytest.raises(HTTPException) as exc:
        FilesWorkspaceService.get_content(DummyDB(), "user-1", "base", "file.bin")
    assert exc.value.status_code == 400


def test_update_content_persists(monkeypatch):
    dummy_storage = DummyStorage()
    db = DummyDB()
    record = _record("base/file.txt")

    monkeypatch.setattr(service_module, "storage_backend", dummy_storage)
    monkeypatch.setattr(service_module.FilesService, "upsert_file", lambda *_, **__: record)

    result = FilesWorkspaceService.update_content(
        db,
        "user-1",
        "base",
        "file.txt",
        "Hello",
    )
    assert result["success"] is True
    assert dummy_storage.calls[0][0] == "put"
