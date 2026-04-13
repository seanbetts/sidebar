"""Tests for website processing worker."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

from api.models.website import Website
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


def test_compute_idle_poll_seconds_uses_bounded_backoff(monkeypatch):
    """Idle polls should back off without growing unbounded."""
    from workers import website_processing_worker

    monkeypatch.setattr(
        website_processing_worker.settings,
        "website_worker_poll_seconds",
        2,
    )

    assert website_processing_worker._compute_idle_poll_seconds(1) == 2
    assert website_processing_worker._compute_idle_poll_seconds(2) == 4
    assert website_processing_worker._compute_idle_poll_seconds(3) == 8
    assert website_processing_worker._compute_idle_poll_seconds(4) == 10
    assert website_processing_worker._compute_idle_poll_seconds(8) == 10


def test_worker_loop_backs_off_after_consecutive_idle_polls(monkeypatch):
    """Idle worker loops should progressively sleep longer between empty claims."""
    from workers import website_processing_worker

    class StopLoop(BaseException):
        pass

    class FakeSession:
        def __enter__(self):
            return object()

        def __exit__(self, exc_type, exc, tb):
            return False

    sleep_calls: list[int] = []

    def fake_sleep(seconds: int) -> None:
        sleep_calls.append(seconds)
        if len(sleep_calls) >= 3:
            raise StopLoop()

    monkeypatch.setattr(website_processing_worker, "SessionLocal", lambda: FakeSession())
    monkeypatch.setattr(website_processing_worker, "_set_worker_scope", lambda _db: None)
    monkeypatch.setattr(website_processing_worker, "_cleanup_old_jobs", lambda _db: 0)
    monkeypatch.setattr(website_processing_worker, "_requeue_stalled_jobs", lambda _db: None)
    monkeypatch.setattr(website_processing_worker, "_claim_job", lambda _db, _worker_id: None)
    monkeypatch.setattr(website_processing_worker.time, "sleep", fake_sleep)
    monkeypatch.setattr(
        website_processing_worker.settings,
        "website_worker_poll_seconds",
        2,
    )

    try:
        website_processing_worker._run_worker_loop("worker-1")
    except StopLoop:
        pass

    assert sleep_calls == [2, 4, 8]


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


def test_process_job_initializes_executor_with_configured_paths(test_db, monkeypatch):
    """Worker should construct SkillExecutor with configured skill and workspace roots."""
    from api.services.agent.skills import executor as executor_module
    from workers import website_processing_worker

    website_id = uuid4()
    captured: dict[str, object] = {}

    class FakeExecutor:
        def __init__(self, skills_dir, workspace_base):
            captured["skills_dir"] = skills_dir
            captured["workspace_base"] = workspace_base

        async def execute(self, *args, **kwargs):
            return {"success": True, "data": {"id": str(website_id)}}

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="processing",
        worker_id="worker-1",
        lease_expires_at=datetime.now(UTC) + timedelta(minutes=1),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    monkeypatch.setattr(executor_module, "SkillExecutor", FakeExecutor)

    website_processing_worker._process_job(test_db, job)
    test_db.refresh(job)

    assert captured == {
        "skills_dir": website_processing_worker.settings.skills_dir,
        "workspace_base": website_processing_worker.settings.workspace_base,
    }
    assert job.status == "completed"
    assert job.website_id == website_id


def test_process_job_closes_preflight_transaction_before_external_save(
    test_db, monkeypatch
):
    """Worker should not hold a DB transaction open while the save script runs."""
    from api.services.agent.skills import executor as executor_module
    from workers import website_processing_worker

    website_id = uuid4()
    observed: dict[str, bool] = {}

    existing_website = Website(
        id=website_id,
        user_id="test-user",
        url="https://example.com/preflight",
        url_full="https://example.com/preflight",
        domain="example.com",
        title="Existing",
        content="Existing content",
        source="web",
        metadata_={"pinned": False, "archived": False},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
        last_opened_at=None,
        deleted_at=None,
    )
    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com/preflight",
        status="processing",
        worker_id="worker-1",
        lease_expires_at=datetime.now(UTC) + timedelta(minutes=1),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add_all([existing_website, job])
    test_db.commit()

    class FakeExecutor:
        def __init__(self, *_args, **_kwargs):
            pass

        async def execute(self, *_args, **_kwargs):
            observed["in_transaction"] = test_db.in_transaction()
            return {"success": True, "data": {"id": str(existing_website.id)}}

    monkeypatch.setattr(executor_module, "SkillExecutor", FakeExecutor)

    assert test_db.in_transaction() is False

    website_processing_worker._process_job(test_db, job)
    test_db.refresh(job)

    assert observed["in_transaction"] is False
    assert job.status == "completed"
    assert job.website_id == existing_website.id


def test_process_job_marks_failed_when_executor_init_raises(test_db, monkeypatch):
    """Worker should fail the claimed job when executor setup crashes."""
    from api.services.agent.skills import executor as executor_module
    from workers import website_processing_worker

    class RaisingExecutor:
        def __init__(self, *_args, **_kwargs):
            raise RuntimeError("executor init failed")

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com",
        status="processing",
        worker_id="worker-1",
        lease_expires_at=datetime.now(UTC) + timedelta(minutes=1),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    monkeypatch.setattr(executor_module, "SkillExecutor", RaisingExecutor)

    website_processing_worker._process_job(test_db, job)
    test_db.refresh(job)

    assert job.status == "failed"
    assert job.error_message == "executor init failed"


def test_process_job_soft_deletes_website_when_canceled_midflight(
    test_db, monkeypatch
):
    """Worker should remove a late-created website when the job was canceled."""
    from api.services.agent.skills import executor as executor_module
    from api.services.website_processing_service import WebsiteProcessingService
    from workers import website_processing_worker

    website_id = uuid4()

    class FakeExecutor:
        def __init__(self, *_args, **_kwargs):
            pass

        async def execute(self, *_args, **_kwargs):
            website = Website(
                id=website_id,
                user_id="test-user",
                url="https://example.com/cancel-me",
                url_full="https://example.com/cancel-me",
                domain="example.com",
                title="Cancel Me",
                content="Content",
                source="web",
                metadata_={"pinned": False, "archived": False},
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
                last_opened_at=None,
                deleted_at=None,
            )
            test_db.add(website)
            test_db.commit()
            WebsiteProcessingService.update_job(test_db, job.id, status="canceled")
            return {"success": True, "data": {"id": str(website_id)}}

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com/cancel-me",
        status="processing",
        worker_id="worker-1",
        lease_expires_at=datetime.now(UTC) + timedelta(minutes=1),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    monkeypatch.setattr(executor_module, "SkillExecutor", FakeExecutor)

    website_processing_worker._process_job(test_db, job)
    test_db.refresh(job)

    website = test_db.query(Website).filter(Website.id == website_id).first()
    assert website is not None
    assert job.status == "canceled"
    assert website.deleted_at is not None


def test_process_job_restores_existing_website_when_repeated_save_is_canceled(
    test_db, monkeypatch
):
    """Worker should restore an existing website row when a repeated save is canceled."""
    from api.services.agent.skills import executor as executor_module
    from api.services.website_processing_service import WebsiteProcessingService
    from workers import website_processing_worker

    existing_website = Website(
        id=uuid4(),
        user_id="test-user",
        url="https://example.com/existing",
        url_full="https://example.com/existing",
        domain="example.com",
        title="Original Title",
        content="Original content",
        source="web",
        metadata_={"pinned": True, "archived": False},
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
        last_opened_at=None,
        deleted_at=None,
    )
    test_db.add(existing_website)
    test_db.commit()

    class FakeExecutor:
        def __init__(self, *_args, **_kwargs):
            pass

        async def execute(self, *_args, **_kwargs):
            website = test_db.query(Website).filter(Website.id == existing_website.id).one()
            website.title = "Updated Title"
            website.content = "Updated content"
            website.metadata_ = {"pinned": False, "archived": False}
            website.deleted_at = None
            test_db.commit()
            WebsiteProcessingService.update_job(test_db, job.id, status="canceled")
            return {"success": True, "data": {"id": str(existing_website.id)}}

    job = WebsiteProcessingJob(
        user_id="test-user",
        url="https://example.com/existing",
        status="processing",
        worker_id="worker-1",
        lease_expires_at=datetime.now(UTC) + timedelta(minutes=1),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    monkeypatch.setattr(executor_module, "SkillExecutor", FakeExecutor)

    website_processing_worker._process_job(test_db, job)
    test_db.refresh(job)
    test_db.refresh(existing_website)

    assert job.status == "canceled"
    assert existing_website.deleted_at is None
    assert existing_website.title == "Original Title"
    assert existing_website.content == "Original content"
    assert existing_website.metadata_ == {"pinned": True, "archived": False}
