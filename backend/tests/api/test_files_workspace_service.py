import uuid
from datetime import UTC, datetime

import pytest
from api.db.base import Base
from api.models.file_ingestion import FileDerivative, IngestedFile
from api.services import files_workspace_service as files_workspace_module
from api.services.files_workspace_service import FilesWorkspaceService
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


@pytest.fixture
def db_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"

    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)

    Session = sessionmaker(bind=connection)
    session = Session()

    try:
        yield session
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()


def _create_file(
    db_session,
    user_id: str,
    path: str,
    *,
    source_metadata: dict | None = None,
) -> IngestedFile:
    record = IngestedFile(
        id=uuid.uuid4(),
        user_id=user_id,
        filename_original=path.split("/")[-1],
        path=path,
        mime_original="text/plain",
        size_bytes=10,
        created_at=datetime.now(UTC),
        source_metadata=source_metadata,
    )
    db_session.add(record)
    db_session.commit()
    return record


def _create_derivative(
    db_session, file_id: uuid.UUID, storage_key: str
) -> FileDerivative:
    derivative = FileDerivative(
        id=uuid.uuid4(),
        file_id=file_id,
        kind="ai_md",
        storage_key=storage_key,
        mime="text/plain",
        size_bytes=10,
        created_at=datetime.now(UTC),
    )
    db_session.add(derivative)
    db_session.commit()
    return derivative


def test_delete_marks_file_deleted_when_storage_fails(db_session, monkeypatch):
    record = _create_file(db_session, "user-1", "docs/file.txt")
    _create_derivative(db_session, record.id, "key-1")

    class FailingStorage:
        def delete_object(self, _key: str) -> None:
            raise RuntimeError("storage down")

    monkeypatch.setattr(files_workspace_module, "storage_backend", FailingStorage())

    FilesWorkspaceService.delete(db_session, "user-1", "", "docs/file.txt")

    refreshed = (
        db_session.query(IngestedFile).filter(IngestedFile.id == record.id).first()
    )
    assert refreshed.deleted_at is not None
    remaining = (
        db_session.query(FileDerivative)
        .filter(FileDerivative.file_id == record.id)
        .all()
    )
    assert len(remaining) == 1


def test_delete_removes_derivatives_when_storage_succeeds(db_session, monkeypatch):
    record = _create_file(db_session, "user-1", "docs/ok.txt")
    _create_derivative(db_session, record.id, "key-2")

    class OkStorage:
        def delete_object(self, _key: str) -> None:
            return None

    monkeypatch.setattr(files_workspace_module, "storage_backend", OkStorage())

    FilesWorkspaceService.delete(db_session, "user-1", "", "docs/ok.txt")

    remaining = (
        db_session.query(FileDerivative)
        .filter(FileDerivative.file_id == record.id)
        .all()
    )
    assert remaining == []


def test_get_tree_hides_website_transcript_files(db_session):
    _create_file(
        db_session,
        "user-1",
        "hidden.md",
        source_metadata={"website_transcript": True},
    )
    _create_file(db_session, "user-1", "visible.md")

    tree = FilesWorkspaceService.get_tree(db_session, "user-1", "")
    children = tree.get("children", [])

    assert any(node.get("name") == "visible.md" for node in children)
    assert not any(node.get("name") == "hidden.md" for node in children)
