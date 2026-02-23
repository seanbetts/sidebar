from contextlib import contextmanager
from pathlib import Path

import pytest

from api.services import skill_file_ops_ingestion


class _FakeStorage:
    def __init__(self) -> None:
        self.put_calls: list[tuple[str, bytes, str | None]] = []

    def put_object(
        self, key: str, data: bytes, content_type: str | None = None
    ) -> None:
        self.put_calls.append((key, data, content_type))


@pytest.fixture
def db_session(test_db):
    return test_db


def test_write_text_persists_shared_staging_source(db_session, monkeypatch):
    @contextmanager
    def fake_session_for_user(_user_id: str):
        yield db_session

    storage = _FakeStorage()
    monkeypatch.setattr(skill_file_ops_ingestion, "session_for_user", fake_session_for_user)
    monkeypatch.setattr(skill_file_ops_ingestion, "get_storage_backend", lambda: storage)

    result = skill_file_ops_ingestion.write_text(
        "user-1",
        "docs/note.txt",
        "hello from write_text",
        wait_for_ready=False,
    )

    expected_key = f"user-1/files/{result['file_id']}/staging/source"
    staging_calls = [call for call in storage.put_calls if call[0] == expected_key]
    assert len(staging_calls) == 1
    assert staging_calls[0][1] == b"hello from write_text"
    assert staging_calls[0][2] == "text/plain"


def test_upload_file_persists_shared_staging_source(db_session, monkeypatch, tmp_path: Path):
    @contextmanager
    def fake_session_for_user(_user_id: str):
        yield db_session

    storage = _FakeStorage()
    monkeypatch.setattr(skill_file_ops_ingestion, "session_for_user", fake_session_for_user)
    monkeypatch.setattr(skill_file_ops_ingestion, "get_storage_backend", lambda: storage)

    local_path = tmp_path / "sample.mp4"
    local_path.write_bytes(b"video-bytes")

    record = skill_file_ops_ingestion.upload_file(
        "user-1",
        "files/videos/sample.mp4",
        local_path,
        content_type="video/mp4",
    )

    expected_key = f"user-1/files/{record.id}/staging/source"
    staging_calls = [call for call in storage.put_calls if call[0] == expected_key]
    assert len(staging_calls) == 1
    assert staging_calls[0][1] == b"video-bytes"
    assert staging_calls[0][2] == "video/mp4"
