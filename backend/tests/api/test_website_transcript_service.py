import uuid

import pytest
from api.db.base import Base
from api.models.file_ingestion import IngestedFile
from api.services.file_ingestion_service import FileIngestionService
from api.services.website_transcript_service import (
    WebsiteTranscriptService,
    extract_youtube_id,
)
from api.services.websites_service import WebsitesService
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
        db_session.query(IngestedFile).filter(IngestedFile.id == result.file_id).first()
    )
    assert record is not None
    assert record.deleted_at is None


def test_sync_transcripts_for_website_updates_failed_status(db_session):
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

    FileIngestionService.update_job_status(
        db_session,
        result.file_id,
        status="failed",
        stage="failed",
        error_code="VIDEO_TRANSCRIPTION_FAILED",
        error_message="boom",
    )

    updated = WebsiteTranscriptService.sync_transcripts_for_website(
        db_session,
        user_id="user-1",
        website_id=website.id,
    )
    assert updated is True

    refreshed = WebsitesService.get_website(
        db_session, "user-1", website.id, mark_opened=False
    )
    video_id = extract_youtube_id("https://www.youtube.com/watch?v=FUq9qRwrDrI")
    entry = (refreshed.metadata_ or {}).get("youtube_transcripts", {}).get(video_id)
    assert entry["status"] == "failed"
    assert entry["error"] == "boom"


def test_update_transcript_status_clears_error_on_ready(db_session):
    website = WebsitesService.save_website(
        db_session,
        "user-1",
        url="https://example.com/path",
        title="Example",
        content="Content",
        source="https://example.com/path",
    )
    url = "https://www.youtube.com/watch?v=FUq9qRwrDrI"
    video_id = extract_youtube_id(url)
    assert video_id is not None

    WebsiteTranscriptService.update_transcript_status(
        db_session,
        user_id="user-1",
        website_id=website.id,
        youtube_url=url,
        status="retrying",
        file_id="file-1",
        error="temporary failure",
    )
    WebsiteTranscriptService.update_transcript_status(
        db_session,
        user_id="user-1",
        website_id=website.id,
        youtube_url=url,
        status="ready",
        file_id="file-1",
    )

    refreshed = WebsitesService.get_website(
        db_session, "user-1", website.id, mark_opened=False
    )
    entry = (refreshed.metadata_ or {}).get("youtube_transcripts", {}).get(video_id)
    assert entry["status"] == "ready"
    assert "error" not in entry
