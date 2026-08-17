"""Tests for read-only durable worker queue-demand inspection."""

from dataclasses import FrozenInstanceError
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.worker_queue_demand_service import (
    WorkerQueueDemand,
    WorkerQueueDemandService,
)

NOW = datetime(2026, 8, 4, 12, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    ("status", "lease_offset", "expected"),
    [
        ("queued", None, True),
        ("queued", -1, True),
        ("queued", 0, True),
        ("queued", 30, False),
        ("processing", -1, True),
        ("processing", 0, False),
        ("processing", 30, False),
        ("completed", None, False),
        ("failed", None, False),
    ],
)
def test_website_demand_matches_claimable_or_recoverable_work(
    test_db, status, lease_offset, expected
):
    """Website demand exists only for queued or expired-processing jobs."""
    lease = None if lease_offset is None else NOW + timedelta(seconds=lease_offset)
    test_db.add(
        WebsiteProcessingJob(
            user_id="test-user",
            url="https://example.com",
            status=status,
            lease_expires_at=lease,
            created_at=NOW,
            updated_at=NOW,
        )
    )
    test_db.commit()

    result = WorkerQueueDemandService.inspect(test_db, now=NOW)

    assert result.website is expected
    assert result.ingestion is False


@pytest.mark.parametrize(
    ("status", "lease_offset", "expected"),
    [
        ("queued", None, True),
        ("queued", -1, True),
        ("queued", 0, True),
        ("queued", 30, False),
        ("processing", -1, True),
        ("processing", 0, False),
        ("processing", 30, False),
        ("ready", None, False),
        ("failed", None, False),
    ],
)
def test_ingestion_demand_matches_claimable_or_recoverable_work(
    test_db, status, lease_offset, expected
):
    """Ingestion demand exists only for active-parent queued or expired jobs."""
    file_id = uuid4()
    lease = None if lease_offset is None else NOW + timedelta(seconds=lease_offset)
    test_db.add(
        IngestedFile(
            id=file_id,
            user_id="test-user",
            filename_original="sample.pdf",
            mime_original="application/pdf",
            size_bytes=123,
            created_at=NOW,
            updated_at=NOW,
            deleted_at=None,
        )
    )
    test_db.flush()
    test_db.add(
        FileProcessingJob(
            file_id=file_id,
            status=status,
            lease_expires_at=lease,
            updated_at=NOW,
        )
    )
    test_db.commit()

    result = WorkerQueueDemandService.inspect(test_db, now=NOW)

    assert result.ingestion is expected
    assert result.website is False


def test_empty_queues_have_no_demand(test_db):
    """Demand is false when neither durable queue has a persisted job."""
    result = WorkerQueueDemandService.inspect(test_db, now=NOW)

    assert result == WorkerQueueDemand(website=False, ingestion=False)


def test_inspection_does_not_flush_pending_jobs(test_db):
    """Inspection does not persist a caller's pending job through autoflush."""
    pending_job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://pending.example.com",
        status="queued",
        created_at=NOW,
        updated_at=NOW,
    )
    test_db.add(pending_job)

    result = WorkerQueueDemandService.inspect(test_db, now=NOW)

    with test_db.no_autoflush:
        persisted_job = (
            test_db.query(WebsiteProcessingJob)
            .filter(WebsiteProcessingJob.url == pending_job.url)
            .first()
        )
    assert result == WorkerQueueDemand(website=False, ingestion=False)
    assert pending_job in test_db.new
    assert persisted_job is None


def test_soft_deleted_ingestion_parent_does_not_create_demand(test_db):
    """A queued ingestion job is ignored when its file has been soft deleted."""
    file_id = uuid4()
    test_db.add(
        IngestedFile(
            id=file_id,
            user_id="test-user",
            filename_original="deleted.pdf",
            mime_original="application/pdf",
            size_bytes=123,
            created_at=NOW,
            updated_at=NOW,
            deleted_at=NOW,
        )
    )
    test_db.flush()
    test_db.add(
        FileProcessingJob(
            file_id=file_id,
            status="queued",
            lease_expires_at=None,
            updated_at=NOW,
        )
    )
    test_db.commit()

    result = WorkerQueueDemandService.inspect(test_db, now=NOW)

    assert result.ingestion is False


def test_inspection_does_not_mutate_job_state(test_db):
    """Demand inspection only reads queued jobs and their current lease state."""
    file_id = uuid4()
    ingestion_file = IngestedFile(
        id=file_id,
        user_id="test-user",
        filename_original="sample.pdf",
        mime_original="application/pdf",
        size_bytes=123,
        created_at=NOW,
        updated_at=NOW,
        deleted_at=None,
    )
    ingestion_job = FileProcessingJob(
        file_id=file_id,
        status="queued",
        worker_id="ingestion-worker",
        lease_expires_at=NOW - timedelta(seconds=1),
        updated_at=NOW,
    )
    website_job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="processing",
        worker_id="website-worker",
        lease_expires_at=NOW - timedelta(seconds=1),
        created_at=NOW,
        updated_at=NOW,
    )
    test_db.add(ingestion_file)
    test_db.flush()
    test_db.add_all([ingestion_job, website_job])
    test_db.commit()

    before = {
        "ingestion": _job_snapshot(ingestion_job),
        "website": _job_snapshot(website_job),
    }

    result = WorkerQueueDemandService.inspect(test_db, now=NOW)

    test_db.refresh(ingestion_job)
    test_db.refresh(website_job)
    assert result == WorkerQueueDemand(ingestion=True, website=True)
    assert _job_snapshot(ingestion_job) == before["ingestion"]
    assert _job_snapshot(website_job) == before["website"]


def test_queue_demand_result_is_immutable():
    """Queue-demand snapshots cannot be mutated after inspection."""
    result = WorkerQueueDemand(ingestion=True, website=False)

    with pytest.raises(FrozenInstanceError):
        result.ingestion = False


def test_queue_demand_positional_order_matches_interface():
    """Positional construction preserves the public website-then-ingestion order."""
    result = WorkerQueueDemand(True, False)

    assert result.website is True
    assert result.ingestion is False


def _job_snapshot(job: FileProcessingJob | WebsiteProcessingJob) -> tuple:
    """Return the persisted worker-state fields that inspection must preserve."""
    return (job.status, job.lease_expires_at, job.worker_id, job.updated_at)
