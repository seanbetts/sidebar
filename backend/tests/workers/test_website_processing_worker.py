"""Tests for website processing worker."""

import threading
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
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


def test_compute_idle_poll_seconds_preserves_interactive_poll_latency(monkeypatch):
    """Interactive website saves should keep the worker on a short fixed poll."""
    from workers import website_processing_worker

    monkeypatch.setattr(
        website_processing_worker.settings,
        "website_worker_poll_seconds",
        2,
    )

    assert website_processing_worker._compute_idle_poll_seconds(1) == 2
    assert website_processing_worker._compute_idle_poll_seconds(2) == 2
    assert website_processing_worker._compute_idle_poll_seconds(3) == 2
    assert website_processing_worker._compute_idle_poll_seconds(8) == 2


def test_worker_loop_keeps_short_sleep_after_consecutive_idle_polls(monkeypatch):
    """Idle website worker loops should preserve a short wake-up latency."""
    from workers import website_processing_worker

    class StopLoop(BaseException):
        pass

    class FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def in_transaction(self) -> bool:
            return False

        def rollback(self) -> None:
            return None

    sleep_calls: list[int] = []

    def fake_sleep(seconds: int) -> None:
        sleep_calls.append(seconds)
        if len(sleep_calls) >= 3:
            raise StopLoop()

    monkeypatch.setattr(
        website_processing_worker, "SessionLocal", lambda: FakeSession()
    )
    monkeypatch.setattr(
        website_processing_worker, "_set_worker_scope", lambda _db: None
    )
    monkeypatch.setattr(website_processing_worker, "_cleanup_old_jobs", lambda _db: 0)
    monkeypatch.setattr(
        website_processing_worker, "_requeue_stalled_jobs", lambda _db: None
    )
    monkeypatch.setattr(
        website_processing_worker, "_claim_job", lambda _db, _worker_id: None
    )
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

    assert sleep_calls == [2, 2, 2]


def test_worker_loop_rolls_back_before_sleeping_on_empty_queue(monkeypatch):
    """Empty queue polls should not leave the session idle in transaction."""
    from workers import website_processing_worker

    class StopLoop(BaseException):
        pass

    class FakeSession:
        def __init__(self) -> None:
            self.transaction_open = False
            self.rollback_calls = 0

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def in_transaction(self) -> bool:
            return self.transaction_open

        def rollback(self) -> None:
            self.rollback_calls += 1
            self.transaction_open = False

    fake_session = FakeSession()
    observed: dict[str, int | bool] = {}

    def fake_claim_job(db, _worker_id):
        db.transaction_open = True
        return None

    def fake_sleep(_seconds: int) -> None:
        observed["in_transaction_during_sleep"] = fake_session.in_transaction()
        observed["rollback_calls"] = fake_session.rollback_calls
        raise StopLoop()

    monkeypatch.setattr(website_processing_worker, "SessionLocal", lambda: fake_session)
    monkeypatch.setattr(
        website_processing_worker, "_set_worker_scope", lambda _db: None
    )
    monkeypatch.setattr(website_processing_worker, "_cleanup_old_jobs", lambda _db: 0)
    monkeypatch.setattr(
        website_processing_worker, "_requeue_stalled_jobs", lambda _db: None
    )
    monkeypatch.setattr(website_processing_worker, "_claim_job", fake_claim_job)
    monkeypatch.setattr(website_processing_worker.time, "sleep", fake_sleep)

    try:
        website_processing_worker._run_worker_loop("worker-1")
    except StopLoop:
        pass

    assert observed == {
        "in_transaction_during_sleep": False,
        "rollback_calls": 1,
    }


def test_worker_loop_completes_job_claimed_during_stop_race(monkeypatch):
    """A job claimed just before stop is set must finish before the loop returns."""
    from workers import website_processing_worker
    from workers.idle_exit import IdleExitTracker

    class FakeClock:
        def __init__(self) -> None:
            self.elapsed = 0.0

        def __call__(self) -> float:
            return self.elapsed

        def advance(self, seconds: float) -> None:
            self.elapsed += seconds

    class FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    clock = FakeClock()
    idle_tracker = IdleExitTracker(30, monotonic=clock)
    stop_event = threading.Event()
    job = SimpleNamespace(id=uuid4(), user_id="test-user")
    processed_jobs: list[object] = []
    claims = 0

    def fake_claim_job(_db, _worker_id):
        nonlocal claims
        claims += 1
        stop_event.set()
        return job

    def fake_process_job(_db, claimed_job) -> None:
        clock.advance(60)
        assert idle_tracker.should_exit() is False
        processed_jobs.append(claimed_job)

    monkeypatch.setattr(website_processing_worker, "SessionLocal", FakeSession)
    monkeypatch.setattr(
        website_processing_worker, "_set_worker_scope", lambda _db: None
    )
    monkeypatch.setattr(website_processing_worker, "_cleanup_old_jobs", lambda _db: 0)
    monkeypatch.setattr(
        website_processing_worker, "_requeue_stalled_jobs", lambda _db: None
    )
    monkeypatch.setattr(website_processing_worker, "_claim_job", fake_claim_job)
    monkeypatch.setattr(website_processing_worker, "_process_job", fake_process_job)
    monkeypatch.setattr(
        website_processing_worker,
        "_start_heartbeat",
        lambda _job_id, _user_id: lambda: None,
    )

    website_processing_worker._run_worker_loop(
        "worker-1",
        stop_event=stop_event,
        idle_tracker=idle_tracker,
    )

    assert claims == 1
    assert processed_jobs == [job]
    assert idle_tracker.should_exit() is False
    clock.advance(30)
    assert idle_tracker.should_exit() is True


def test_main_coordinates_idle_exit_across_two_worker_threads(monkeypatch):
    """Main must stop both loops only after process-wide inactivity."""
    from workers import website_processing_worker
    from workers.idle_exit import IdleExitTracker

    class FakeClock:
        def __init__(self) -> None:
            self.elapsed = 0.0
            self.lock = threading.Lock()

        def __call__(self) -> float:
            with self.lock:
                return self.elapsed

        def advance(self, seconds: float) -> None:
            with self.lock:
                self.elapsed += seconds

    class ObservedIdleExitTracker(IdleExitTracker):
        def __init__(self, timeout_seconds: float) -> None:
            super().__init__(timeout_seconds, monotonic=clock)
            self.checks: list[tuple[float, bool]] = []
            self.check_condition = threading.Condition()

        def should_exit(self) -> bool:
            result = super().should_exit()
            with self.check_condition:
                self.checks.append((clock(), result))
                self.check_condition.notify_all()
            return result

        def wait_for_check(self, elapsed: float) -> bool:
            with self.check_condition:
                observed = self.check_condition.wait_for(
                    lambda: any(check == elapsed for check, _ in self.checks),
                    timeout=1,
                )
                assert observed
                return next(
                    result
                    for check, result in reversed(self.checks)
                    if check == elapsed
                )

    clock = FakeClock()
    trackers: list[ObservedIdleExitTracker] = []
    worker_calls: list[tuple[threading.Event, ObservedIdleExitTracker]] = []
    calls_lock = threading.Lock()
    both_workers_started = threading.Event()
    active_job_started = threading.Event()
    release_active_job = threading.Event()
    active_job_finished = threading.Event()
    main_errors: list[BaseException] = []

    def make_tracker(timeout_seconds: float) -> ObservedIdleExitTracker:
        tracker = ObservedIdleExitTracker(timeout_seconds)
        trackers.append(tracker)
        return tracker

    def fake_worker_loop(
        _worker_id: str,
        *,
        stop_event: threading.Event | None = None,
        idle_tracker: ObservedIdleExitTracker | None = None,
    ) -> None:
        assert stop_event is not None
        assert idle_tracker is not None
        with calls_lock:
            worker_calls.append((stop_event, idle_tracker))
            is_active_worker = len(worker_calls) == 1
            if len(worker_calls) == 2:
                both_workers_started.set()

        if is_active_worker:
            idle_tracker.job_started()
            active_job_started.set()
            assert release_active_job.wait(timeout=1)
            idle_tracker.job_finished()
            active_job_finished.set()

        assert stop_event.wait(timeout=2)

    def run_main() -> None:
        try:
            website_processing_worker.main()
        except BaseException as exc:
            main_errors.append(exc)

    monkeypatch.setattr(website_processing_worker, "IdleExitTracker", make_tracker)
    monkeypatch.setattr(website_processing_worker, "_run_worker_loop", fake_worker_loop)
    monkeypatch.setattr(
        website_processing_worker,
        "initialize_script_sentry",
        lambda *_args, **_kwargs: True,
    )
    monkeypatch.setattr(
        website_processing_worker.settings,
        "website_worker_concurrency",
        2,
    )
    monkeypatch.setattr(
        website_processing_worker.settings,
        "website_worker_idle_exit_seconds",
        30,
    )

    main_thread = threading.Thread(target=run_main)
    main_thread.start()
    assert both_workers_started.wait(timeout=1)
    assert active_job_started.wait(timeout=1)
    assert len(trackers) == 1

    clock.advance(60)
    assert trackers[0].wait_for_check(60) is False
    assert worker_calls[0][0].is_set() is False

    release_active_job.set()
    assert active_job_finished.wait(timeout=1)
    clock.advance(29)
    assert trackers[0].wait_for_check(89) is False

    clock.advance(1)
    main_thread.join(timeout=2)

    assert main_thread.is_alive() is False
    assert main_errors == []
    assert len(worker_calls) == 2
    assert worker_calls[0][0] is worker_calls[1][0]
    assert worker_calls[0][1] is worker_calls[1][1]
    assert worker_calls[0][0].is_set() is True


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
        lambda worker_id, **_kwargs: started_worker_ids.append(worker_id),
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


def test_process_job_soft_deletes_website_when_canceled_midflight(test_db, monkeypatch):
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
            website = (
                test_db.query(Website).filter(Website.id == existing_website.id).one()
            )
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
