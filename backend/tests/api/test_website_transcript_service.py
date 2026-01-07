import uuid

import pytest
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker

from api.db.base import Base
from api.models.file_ingestion import IngestedFile
from api.services.file_ingestion_service import FileIngestionService
from api.services.website_transcript_service import WebsiteTranscriptService
from api.services.websites_service import WebsitesService


@pytest.fixture
def db_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(isolation_level="AUTOCOMMIT")
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


def test_enqueue_youtube_transcript_keeps_ingestion_visible(db_session):
    website = WebsitesService.save_website(
        db_session,
        "user-1",
        url="https://example.com/path",
        title="Example",
        content="Content",
        source="https://example.com/path",
    )

    result = WebsiteTranscriptService.enqueue_youtube_transcript(
        db_session,
        "user-1",
        website.id,
        "https://www.youtube.com/watch?v=FUq9qRwrDrI",
    )

    assert result.file_id is not None
    record = (
        db_session.query(IngestedFile)
        .filter(IngestedFile.id == result.file_id)
        .first()
    )
    assert record is not None
    assert record.deleted_at is None
