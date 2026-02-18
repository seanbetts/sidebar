from datetime import timedelta

import pytest
from api.exceptions import ConflictError
from api.models.file_ingestion import FileDerivative, FileProcessingJob
from api.services.file_ingestion_service import FileIngestionService


@pytest.fixture
def db_session(test_db):
    return test_db


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


def test_update_filename_conflict(db_session):
    file_record = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="report.pdf",
        path="report.pdf",
        mime_original="application/pdf",
        size_bytes=10,
    )[0]
    stale = file_record.updated_at - timedelta(seconds=10)

    with pytest.raises(ConflictError):
        FileIngestionService.update_filename(
            db_session,
            "user-1",
            file_record.id,
            "renamed.pdf",
            client_updated_at=stale,
        )


def test_list_ingestions_for_sidebar_includes_ready_when_active_is_capped(db_session):
    for i in range(6):
        record = FileIngestionService.create_ingestion(
            db_session,
            "user-1",
            filename_original=f"active-{i}.txt",
            path=f"active-{i}.txt",
            mime_original="text/plain",
            size_bytes=10,
        )[0]
        FileIngestionService.update_job_status(
            db_session, record.id, status="processing", stage="validating"
        )

    for i in range(4):
        record = FileIngestionService.create_ingestion(
            db_session,
            "user-1",
            filename_original=f"ready-{i}.txt",
            path=f"ready-{i}.txt",
            mime_original="text/plain",
            size_bytes=10,
        )[0]
        FileIngestionService.update_job_status(
            db_session, record.id, status="ready", stage="ready"
        )

    records = FileIngestionService.list_ingestions_for_sidebar(
        db_session, "user-1", limit=6, active_limit=2
    )
    statuses = [FileIngestionService.get_job(db_session, item.id).status for item in records]

    assert len(records) == 6
    assert statuses.count("processing") == 2
    assert statuses.count("ready") == 4


def test_list_ingestions_for_sidebar_backfills_active_when_no_completed_items(db_session):
    for i in range(5):
        record = FileIngestionService.create_ingestion(
            db_session,
            "user-1",
            filename_original=f"active-only-{i}.txt",
            path=f"active-only-{i}.txt",
            mime_original="text/plain",
            size_bytes=10,
        )[0]
        FileIngestionService.update_job_status(
            db_session, record.id, status="processing", stage="validating"
        )

    records = FileIngestionService.list_ingestions_for_sidebar(
        db_session, "user-1", limit=4, active_limit=2
    )

    assert len(records) == 4


def test_ensure_job_record_backfills_ready_when_derivatives_exist(db_session):
    record = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="legacy.pdf",
        path="legacy.pdf",
        mime_original="application/pdf",
        size_bytes=10,
    )[0]
    db_session.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
    db_session.query(FileProcessingJob).filter(
        FileProcessingJob.file_id == record.id
    ).delete()
    db_session.add(
        FileDerivative(
            file_id=record.id,
            kind="viewer_pdf",
            storage_key=f"user-1/files/{record.id}/derivatives/viewer.pdf",
            mime="application/pdf",
            size_bytes=256,
            sha256=None,
        )
    )
    db_session.commit()

    job = FileIngestionService.ensure_job_record(
        db_session,
        record,
        has_derivatives=True,
    )

    assert job.status == "ready"
    assert job.stage == "ready"


def test_ensure_job_record_backfills_failed_without_derivatives_or_source(db_session):
    record = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="legacy.txt",
        path="legacy.txt",
        mime_original="text/plain",
        size_bytes=10,
    )[0]
    db_session.query(FileProcessingJob).filter(
        FileProcessingJob.file_id == record.id
    ).delete()
    db_session.commit()

    job = FileIngestionService.ensure_job_record(
        db_session,
        record,
        has_derivatives=False,
    )

    assert job.status == "failed"
    assert job.stage == "failed"
    assert job.error_code == "SOURCE_MISSING"
