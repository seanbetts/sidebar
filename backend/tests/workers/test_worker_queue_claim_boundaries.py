"""Claim-boundary tests shared by durable worker queues."""

from datetime import UTC, datetime
from uuid import uuid4

from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website_processing_job import WebsiteProcessingJob
from workers import ingestion_worker, website_processing_worker


def test_website_worker_claims_queued_job_with_lease_at_current_time(
    test_db, monkeypatch
):
    """Website worker claims queued work when its lease is due exactly now."""
    now = datetime(2026, 8, 4, 12, 0, tzinfo=UTC)
    monkeypatch.setattr(website_processing_worker, "_now", lambda: now)
    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="queued",
        lease_expires_at=now,
        created_at=now,
        updated_at=now,
    )
    test_db.add(job)
    test_db.commit()

    claimed = website_processing_worker._claim_job(test_db, "worker-1")

    assert claimed is not None
    assert claimed.id == job.id


def test_ingestion_worker_claims_queued_job_with_lease_at_current_time(
    test_db, monkeypatch
):
    """Ingestion worker claims queued work when its lease is due exactly now."""
    now = datetime(2026, 8, 4, 12, 0, tzinfo=UTC)
    monkeypatch.setattr(ingestion_worker, "_now", lambda: now)
    file_id = uuid4()
    test_db.add(
        IngestedFile(
            id=file_id,
            user_id="test-user",
            filename_original="sample.pdf",
            mime_original="application/pdf",
            size_bytes=123,
            created_at=now,
            updated_at=now,
        )
    )
    test_db.flush()
    job = FileProcessingJob(
        file_id=file_id,
        status="queued",
        lease_expires_at=now,
        updated_at=now,
    )
    test_db.add(job)
    test_db.commit()

    claimed = ingestion_worker._claim_job(test_db, "worker-1")

    assert claimed is not None
    assert claimed.id == job.id
