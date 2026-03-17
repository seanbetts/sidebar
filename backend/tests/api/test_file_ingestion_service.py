from datetime import UTC, datetime, timedelta

import pytest
from api.exceptions import ConflictError
from api.models.file_ingestion import FileDerivative, FileProcessingJob
from api.services.file_ingestion_service import FileIngestionService
from api.services import ingestion_job_health_service
from api.services.ingestion_job_health_service import IngestionJobHealthService


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


def test_soft_delete_file_clears_pinned_state(db_session):
    file_record = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="pinned.txt",
        path="pinned.txt",
        mime_original="text/plain",
        size_bytes=10,
    )[0]
    FileIngestionService.update_pinned(db_session, "user-1", file_record.id, True)

    deleted = FileIngestionService.soft_delete_file(db_session, file_record.id)

    assert deleted is not None
    assert deleted.deleted_at is not None
    assert deleted.pinned is False
    assert deleted.pinned_order is None


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


def test_fail_stale_queued_jobs_when_worker_unavailable_marks_failed(db_session):
    record, job = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="queued.txt",
        path="queued.txt",
        mime_original="text/plain",
        size_bytes=10,
    )
    _ = record
    job.updated_at = datetime.now(UTC) - timedelta(minutes=5)
    db_session.commit()

    updated = IngestionJobHealthService.fail_stale_queued_jobs_when_worker_unavailable(
        db_session,
        "user-1",
        queued_ttl_seconds=120,
        worker_heartbeat_ttl_seconds=45,
    )

    refreshed = FileIngestionService.get_job(db_session, job.file_id)
    assert updated == 1
    assert refreshed is not None
    assert refreshed.status == "failed"
    assert refreshed.stage == "failed"
    assert refreshed.error_code == "INGESTION_WORKER_UNAVAILABLE"
    assert (
        refreshed.error_message
        == "Processing is temporarily unavailable. Please retry in a few minutes."
    )


def test_fail_stale_queued_jobs_when_worker_available_keeps_queued(db_session):
    _, stale_queued_job = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="queued.txt",
        path="queued.txt",
        mime_original="text/plain",
        size_bytes=10,
    )
    stale_queued_job.updated_at = datetime.now(UTC) - timedelta(minutes=5)

    _, active_job = FileIngestionService.create_ingestion(
        db_session,
        "user-2",
        filename_original="processing.txt",
        path="processing.txt",
        mime_original="text/plain",
        size_bytes=10,
    )
    active_job.status = "processing"
    active_job.stage = "extracting"
    active_job.updated_at = datetime.now(UTC)
    db_session.commit()

    updated = IngestionJobHealthService.fail_stale_queued_jobs_when_worker_unavailable(
        db_session,
        "user-1",
        queued_ttl_seconds=120,
        worker_heartbeat_ttl_seconds=45,
    )

    refreshed = FileIngestionService.get_job(db_session, stale_queued_job.file_id)
    assert updated == 0
    assert refreshed is not None
    assert refreshed.status == "queued"


def test_fail_stale_queued_jobs_reports_sentry_once(db_session, monkeypatch):
    _, job = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="queued.txt",
        path="queued.txt",
        mime_original="text/plain",
        size_bytes=10,
    )
    job.updated_at = datetime.now(UTC) - timedelta(minutes=5)
    db_session.commit()

    sentry_messages: list[tuple[str, str | None]] = []

    monkeypatch.setattr(
        ingestion_job_health_service.sentry_sdk,
        "capture_message",
        lambda message, *, level=None: sentry_messages.append((message, level)),
    )

    updated = IngestionJobHealthService.fail_stale_queued_jobs_when_worker_unavailable(
        db_session,
        "user-1",
        queued_ttl_seconds=120,
        worker_heartbeat_ttl_seconds=45,
    )

    assert updated == 1
    assert sentry_messages == [
        ("Ingestion worker unavailable for stale queued jobs", "error")
    ]


def test_fail_stale_queued_jobs_logs_worker_unavailable_summary(
    db_session, monkeypatch
):
    _, job = FileIngestionService.create_ingestion(
        db_session,
        "user-1",
        filename_original="queued.txt",
        path="queued.txt",
        mime_original="text/plain",
        size_bytes=10,
    )
    stale_age = timedelta(minutes=5)
    job.updated_at = datetime.now(UTC) - stale_age
    db_session.commit()

    log_messages: list[str] = []

    monkeypatch.setattr(
        ingestion_job_health_service.logger,
        "error",
        lambda message, *args: log_messages.append(message % args if args else message),
    )
    monkeypatch.setattr(
        ingestion_job_health_service.sentry_sdk,
        "capture_message",
        lambda message, *, level=None: None,
    )

    updated = IngestionJobHealthService.fail_stale_queued_jobs_when_worker_unavailable(
        db_session,
        "user-1",
        queued_ttl_seconds=120,
        worker_heartbeat_ttl_seconds=45,
    )

    assert updated == 1
    assert log_messages == [
        "Ingestion worker unavailable for user_id=user-1; failing 1 stale queued jobs"
    ]
