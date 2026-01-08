from datetime import UTC, datetime, timedelta
from uuid import uuid4

from api.models.file_ingestion import FileProcessingJob, IngestedFile
from workers import ingestion_worker


def _make_ingested_file(test_db, file_id):
    record = IngestedFile(
        id=file_id,
        user_id="test-user",
        filename_original="sample.pdf",
        mime_original="application/pdf",
        size_bytes=123,
        sha256="abc123",
        created_at=datetime.now(UTC),
    )
    test_db.add(record)
    test_db.commit()
    return record


def test_retryable_error_requeues_with_backoff(test_db):
    file_id = uuid4()
    _make_ingested_file(test_db, file_id)
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="extracting",
        attempts=0,
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    error = ingestion_worker.IngestionError(
        "CONVERSION_TIMEOUT", "timeout", retryable=True
    )
    ingestion_worker._retry_or_fail(test_db, job, error)

    test_db.refresh(job)
    assert job.status == "queued"
    assert job.stage == "queued"
    assert job.error_code == "CONVERSION_TIMEOUT"
    assert job.attempts == 1
    assert job.lease_expires_at is not None
    assert job.lease_expires_at > ingestion_worker._now()


def test_retryable_error_exhausts_attempts(test_db):
    file_id = uuid4()
    _make_ingested_file(test_db, file_id)
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="extracting",
        attempts=ingestion_worker.MAX_ATTEMPTS - 1,
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    error = ingestion_worker.IngestionError(
        "CONVERSION_TIMEOUT", "timeout", retryable=True
    )
    ingestion_worker._retry_or_fail(test_db, job, error)

    test_db.refresh(job)
    assert job.status == "failed"
    assert job.stage == "failed"
    assert job.error_code == "CONVERSION_TIMEOUT"
    assert job.attempts == ingestion_worker.MAX_ATTEMPTS
    assert job.finished_at is not None


def test_requeue_stalled_jobs_marks_retryable(test_db):
    file_id = uuid4()
    _make_ingested_file(test_db, file_id)
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="converting",
        attempts=0,
        updated_at=datetime.now(UTC) - timedelta(minutes=10),
        lease_expires_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    test_db.add(job)
    test_db.commit()

    ingestion_worker._requeue_stalled_jobs(test_db)
    test_db.refresh(job)

    assert job.status == "queued"
    assert job.stage == "queued"
    assert job.error_code == "WORKER_STALLED"
    assert job.attempts == 1
    assert job.lease_expires_at is not None
    assert job.lease_expires_at > ingestion_worker._now()


def test_is_allowed_file_accepts_supported_types():
    assert ingestion_worker._is_allowed_file("application/pdf", "doc.pdf")
    assert ingestion_worker._is_allowed_file("text/plain", "notes.txt")
    assert ingestion_worker._is_allowed_file("image/png", "image.png")
    assert ingestion_worker._is_allowed_file("audio/mpeg", "track.mp3")
    assert ingestion_worker._is_allowed_file("video/mp4", "clip.mp4")
    assert ingestion_worker._is_allowed_file("application/octet-stream", "sheet.xlsx")


def test_is_allowed_file_rejects_unsupported_types():
    assert not ingestion_worker._is_allowed_file(
        "application/octet-stream", "archive.zip"
    )
