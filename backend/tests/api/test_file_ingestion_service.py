import uuid

import pytest
from api.db.base import Base
from api.services.file_ingestion_service import FileIngestionService
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


def test_list_ingestions_filters_by_user(db_session):
    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="a.txt",
        path="a.txt",
        mime_original="text/plain",
        size_bytes=10,
    )
    FileIngestionService.create_ingestion(
        db_session,
        "user-2",
        filename_original="b.txt",
        path="b.txt",
        mime_original="text/plain",
        size_bytes=10,
    )

    records = FileIngestionService.list_ingestions(db_session, "user-1", limit=50)

    assert len(records) == 1
    assert records[0].user_id == "user-1"


def test_update_pinned_assigns_next_order(db_session):
    file_a = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="a.txt",
        path="a.txt",
        mime_original="text/plain",
        size_bytes=10,
    )[0]
    file_b = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="b.txt",
        path="b.txt",
        mime_original="text/plain",
        size_bytes=10,
    )[0]

    FileIngestionService.update_pinned(db_session, "user-1", file_a.id, True)
    FileIngestionService.update_pinned(db_session, "user-1", file_b.id, True)

    refreshed_a = FileIngestionService.get_file(db_session, "user-1", file_a.id)
    refreshed_b = FileIngestionService.get_file(db_session, "user-1", file_b.id)

    assert refreshed_a.pinned_order == 0
    assert refreshed_b.pinned_order == 1


def test_list_ingestions_hides_website_transcripts(db_session):
    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="transcript.md",
        path="transcript.md",
        mime_original="text/markdown",
        size_bytes=10,
        source_metadata={"website_transcript": True},
    )
    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="report.pdf",
        path="report.pdf",
        mime_original="application/pdf",
        size_bytes=10,
    )

    records = FileIngestionService.list_ingestions(db_session, "user-1", limit=50)

    assert len(records) == 1
    assert records[0].filename_original == "report.pdf"


def test_list_ingestions_hides_ai_md_paths(db_session):
    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="ai.md",
        path="files/videos/abc123/ai/ai.md",
        mime_original="text/plain",
        size_bytes=10,
    )
    FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="notes.md",
        path="notes.md",
        mime_original="text/markdown",
        size_bytes=10,
    )

    records = FileIngestionService.list_ingestions(db_session, "user-1", limit=50)

    assert len(records) == 1
    assert records[0].filename_original == "notes.md"
