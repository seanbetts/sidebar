"""Tests for website processing worker."""

from datetime import UTC, datetime, timedelta

from api.models.website_processing_job import WebsiteProcessingJob


def test_claim_job_returns_queued_job(test_db):
    """Worker should claim a queued job and set it to processing."""
    from workers.website_processing_worker import _claim_job

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="queued",
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    claimed = _claim_job(test_db, "worker-1")
    assert claimed is not None
    assert claimed.status == "processing"
    assert claimed.worker_id == "worker-1"
    assert claimed.lease_expires_at is not None


def test_claim_job_skips_processing_with_active_lease(test_db):
    """Worker should not claim a job with an active lease."""
    from workers.website_processing_worker import _claim_job

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="processing",
        worker_id="other-worker",
        lease_expires_at=datetime.now(UTC) + timedelta(minutes=3),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    claimed = _claim_job(test_db, "worker-1")
    assert claimed is None


def test_requeue_stalled_jobs(test_db):
    """Worker should requeue jobs with expired leases."""
    from workers.website_processing_worker import _requeue_stalled_jobs

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="processing",
        worker_id="dead-worker",
        lease_expires_at=datetime.now(UTC) - timedelta(minutes=1),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    _requeue_stalled_jobs(test_db)
    test_db.refresh(job)
    assert job.status == "queued"
    assert job.worker_id is None


def test_main_initializes_sentry_with_worker_script_name(monkeypatch):
    """Website worker main should initialize Sentry with a worker script name."""
    from workers import website_processing_worker

    captured: dict[str, str] = {}
    started_worker_ids: list[str] = []

    def fake_initialize_script_sentry(script_name: str, **kwargs) -> bool:
        captured["script_name"] = script_name
        captured["process_type"] = kwargs.get("process_type", "")
        return True

    monkeypatch.setattr(
        website_processing_worker,
        "initialize_script_sentry",
        fake_initialize_script_sentry,
    )
    monkeypatch.setattr(
        website_processing_worker,
        "_run_worker_loop",
        lambda worker_id: started_worker_ids.append(worker_id),
    )
    monkeypatch.setattr(
        website_processing_worker.settings,
        "website_worker_concurrency",
        1,
    )

    website_processing_worker.main()

    assert captured == {
        "script_name": "workers.website_processing_worker",
        "process_type": "worker",
    }
    assert len(started_worker_ids) == 1
