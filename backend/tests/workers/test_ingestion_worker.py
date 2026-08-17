from datetime import UTC, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import pytest

from api.models.file_ingestion import FileDerivative, FileProcessingJob, IngestedFile
from api.services.file_ingestion_service import FileIngestionService
from api.services.website_transcript_service import WebsiteTranscriptService
from workers import ingestion_worker
from workers.idle_exit import IdleExitTracker


class _DummySession:
    def __init__(self):
        self.info: dict[str, str] = {}
        self.executed: list[str] = []

    def execute(self, statement):
        self.executed.append(str(statement))
        return None


class StopAfterIdleClock:
    def __init__(self) -> None:
        self.elapsed = 0.0

    def __call__(self) -> float:
        return self.elapsed

    def advance(self, seconds: float) -> None:
        self.elapsed += seconds


class EmptySession:
    def __init__(self, events: list[str] | None = None) -> None:
        self.events = events

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def rollback(self) -> None:
        if self.events is not None:
            self.events.append("rollback")


class ObservedIdleExitTracker(IdleExitTracker):
    def __init__(self, timeout_seconds: float, *, monotonic) -> None:
        super().__init__(timeout_seconds, monotonic=monotonic)
        self.started = 0
        self.finished = 0

    def job_started(self) -> None:
        self.started += 1
        super().job_started()

    def job_finished(self) -> None:
        self.finished += 1
        super().job_finished()


def install_empty_ingestion_queue(monkeypatch, *, session_factory=EmptySession) -> None:
    monkeypatch.setattr(ingestion_worker, "SessionLocal", session_factory)
    monkeypatch.setattr(ingestion_worker, "_initialize_worker_sentry", lambda: None)
    monkeypatch.setattr(ingestion_worker, "_ensure_stdio", lambda: None)
    monkeypatch.setattr(ingestion_worker, "_resolve_worker_user_id", lambda: None)
    monkeypatch.setattr(
        ingestion_worker,
        "_enforce_safe_dev_worker_configuration",
        lambda _user_id: None,
    )
    monkeypatch.setattr(
        ingestion_worker,
        "_set_worker_claim_scope",
        lambda _db, _user_id: None,
    )
    monkeypatch.setattr(ingestion_worker, "_requeue_stalled_jobs", lambda _db: None)
    monkeypatch.setattr(ingestion_worker, "_claim_job", lambda _db, _worker_id: None)


def install_claimed_ingestion_job(monkeypatch, *, job, record) -> EmptySession:
    session = EmptySession()
    claims = iter((job, None))
    install_empty_ingestion_queue(monkeypatch, session_factory=lambda: session)
    monkeypatch.setattr(
        ingestion_worker,
        "_claim_job",
        lambda _db, _worker_id: next(claims, None),
    )
    monkeypatch.setattr(ingestion_worker, "_get_file", lambda _db, _job: record)
    monkeypatch.setattr(ingestion_worker, "set_session_user_id", lambda *_args: None)
    monkeypatch.setattr(
        ingestion_worker,
        "_start_heartbeat",
        lambda _job_id, _user_id: lambda: None,
    )
    monkeypatch.setattr(session, "refresh", lambda _record: None, raising=False)
    monkeypatch.setattr(ingestion_worker, "_mark_ready", lambda *_args: None)
    monkeypatch.setattr(ingestion_worker, "_cleanup_staging", lambda *_args: None)
    monkeypatch.setattr(
        ingestion_worker, "_ensure_source_path", lambda _record: Path("/tmp/source")
    )
    monkeypatch.setattr(
        ingestion_worker, "_normalize_mime", lambda *_args: "text/plain"
    )
    monkeypatch.setattr(ingestion_worker, "_should_fast_track", lambda *_args: True)
    return session


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


def _make_youtube_ingested_file(test_db, file_id):
    record = IngestedFile(
        id=file_id,
        user_id="test-user",
        filename_original="YouTube Video",
        mime_original="video/youtube",
        size_bytes=0,
        sha256=None,
        source_url="https://www.youtube.com/watch?v=abc123",
        source_metadata={"provider": "youtube", "video_id": "abc123"},
        created_at=datetime.now(UTC),
    )
    test_db.add(record)
    test_db.commit()
    return record


def _make_youtube_website_transcript_ingested_file(test_db, file_id, website_id):
    record = IngestedFile(
        id=file_id,
        user_id="test-user",
        filename_original="YouTube Video",
        mime_original="video/youtube",
        size_bytes=0,
        sha256=None,
        source_url="https://www.youtube.com/watch?v=abc123",
        source_metadata={
            "provider": "youtube",
            "video_id": "abc123",
            "youtube_url": "https://www.youtube.com/watch?v=abc123",
            "website_id": str(website_id),
            "website_transcript": True,
        },
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


def test_compute_idle_poll_seconds_uses_bounded_backoff():
    assert ingestion_worker._compute_idle_poll_seconds(1) == 2
    assert ingestion_worker._compute_idle_poll_seconds(2) == 4
    assert ingestion_worker._compute_idle_poll_seconds(3) == 8
    assert ingestion_worker._compute_idle_poll_seconds(4) == 10
    assert ingestion_worker._compute_idle_poll_seconds(8) == 10


def test_worker_loop_returns_after_configured_idle_period(monkeypatch):
    clock = StopAfterIdleClock()
    tracker = IdleExitTracker(30, monotonic=clock)
    install_empty_ingestion_queue(monkeypatch)
    monkeypatch.setattr(ingestion_worker.time, "sleep", clock.advance)

    ingestion_worker.worker_loop(idle_tracker=tracker)

    assert clock.elapsed == 34


def test_worker_loop_uses_configured_idle_period_by_default(monkeypatch):
    clock = StopAfterIdleClock()
    configured_timeouts: list[float] = []

    class ConfiguredTracker(IdleExitTracker):
        def __init__(self, timeout_seconds: float) -> None:
            configured_timeouts.append(timeout_seconds)
            super().__init__(timeout_seconds, monotonic=clock)

    def advance_with_limit(seconds: float) -> None:
        clock.advance(seconds)
        if clock.elapsed > 60:
            pytest.fail("configured idle timeout was not applied")

    install_empty_ingestion_queue(monkeypatch)
    monkeypatch.setattr(ingestion_worker, "IdleExitTracker", ConfiguredTracker)
    monkeypatch.setattr(
        ingestion_worker.settings, "ingestion_worker_idle_exit_seconds", 30
    )
    monkeypatch.setattr(ingestion_worker.time, "sleep", advance_with_limit)

    ingestion_worker.worker_loop()

    assert configured_timeouts == [30]
    assert clock.elapsed == 34


def test_worker_loop_rolls_back_before_idle_exit_check(monkeypatch):
    events: list[str] = []

    class ExitingTracker:
        def should_exit(self) -> bool:
            events.append("check")
            return True

    install_empty_ingestion_queue(
        monkeypatch,
        session_factory=lambda: EmptySession(events),
    )
    monkeypatch.setattr(
        ingestion_worker.time,
        "sleep",
        lambda _seconds: pytest.fail("idle exit must happen before sleeping"),
    )

    ingestion_worker.worker_loop(idle_tracker=ExitingTracker())

    assert events[:2] == ["rollback", "check"]


def test_worker_loop_backs_off_after_consecutive_idle_polls(monkeypatch):
    class StopLoop(BaseException):
        pass

    class FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def rollback(self) -> None:
            return None

    sleep_calls: list[int] = []

    def fake_sleep(seconds: int) -> None:
        sleep_calls.append(seconds)
        if len(sleep_calls) >= 4:
            raise StopLoop()

    monkeypatch.setattr(ingestion_worker, "SessionLocal", lambda: FakeSession())
    monkeypatch.setattr(ingestion_worker, "_resolve_worker_user_id", lambda: None)
    monkeypatch.setattr(
        ingestion_worker,
        "_enforce_safe_dev_worker_configuration",
        lambda _user_id: None,
    )
    monkeypatch.setattr(
        ingestion_worker, "_set_worker_claim_scope", lambda _db, _worker_user_id: None
    )
    monkeypatch.setattr(ingestion_worker, "_requeue_stalled_jobs", lambda _db: None)
    monkeypatch.setattr(ingestion_worker, "_claim_job", lambda _db, _worker_id: None)
    monkeypatch.setattr(ingestion_worker.time, "sleep", fake_sleep)

    try:
        ingestion_worker.worker_loop(idle_tracker=IdleExitTracker(0))
    except StopLoop:
        pass

    assert sleep_calls == [2, 4, 8, 10]


def test_active_youtube_job_resets_idle_period_after_finishing(monkeypatch):
    clock = StopAfterIdleClock()
    tracker = ObservedIdleExitTracker(30, monotonic=clock)
    job = SimpleNamespace(id="job-1", file_id="file-1", status="processing")
    record = SimpleNamespace(
        id="file-1",
        user_id="user-1",
        source_url="https://www.youtube.com/watch?v=abc123",
        filename_original="YouTube Video",
        mime_original="video/youtube",
    )
    install_claimed_ingestion_job(monkeypatch, job=job, record=record)

    def process_youtube_job(_db, _job, _record) -> None:
        clock.advance(60)
        assert tracker.should_exit() is False

    monkeypatch.setattr(ingestion_worker, "_process_youtube_job", process_youtube_job)
    monkeypatch.setattr(ingestion_worker.time, "sleep", clock.advance)

    ingestion_worker.worker_loop(idle_tracker=tracker)

    assert tracker.started == 1
    assert tracker.finished == 1
    assert clock.elapsed == 94


@pytest.mark.parametrize(
    "outcome",
    ["youtube", "fast_track", "pipeline", "halted", "retryable", "unexpected"],
)
def test_claimed_job_finishes_once_across_worker_branches(monkeypatch, outcome):
    class StopLoop(BaseException):
        pass

    clock = StopAfterIdleClock()
    tracker = ObservedIdleExitTracker(0, monotonic=clock)
    source_url = (
        "https://www.youtube.com/watch?v=abc123" if outcome == "youtube" else None
    )
    job = SimpleNamespace(
        id="job-1",
        file_id="file-1",
        status="processing",
        lease_expires_at=None,
    )
    record = SimpleNamespace(
        id="file-1",
        user_id="user-1",
        source_url=source_url,
        filename_original="sample.txt",
        mime_original="text/plain",
    )
    install_claimed_ingestion_job(monkeypatch, job=job, record=record)

    def process_youtube_job(_db, _job, _record) -> None:
        return None

    def process_simple_file(_db, _job, _record, _source_path, _mime) -> None:
        if outcome == "halted":
            raise ingestion_worker.IngestionError(
                "JOB_HALTED", "halted", retryable=False
            )
        if outcome == "retryable":
            raise ingestion_worker.IngestionError(
                "STORAGE_UNAVAILABLE", "retry", retryable=True
            )
        if outcome == "unexpected":
            raise RuntimeError("boom")

    retry_lease = object()
    retried_errors: list[ingestion_worker.IngestionError] = []

    def retry_or_fail(_db, retried_job, error) -> None:
        retried_job.status = "queued"
        retried_job.lease_expires_at = retry_lease
        retried_errors.append(error)

    monkeypatch.setattr(ingestion_worker, "_process_youtube_job", process_youtube_job)
    monkeypatch.setattr(ingestion_worker, "_process_simple_file", process_simple_file)
    if outcome == "pipeline":
        monkeypatch.setattr(
            ingestion_worker, "_should_fast_track", lambda *_args: False
        )
        monkeypatch.setattr(ingestion_worker, "PIPELINE_STAGES", ())
    monkeypatch.setattr(ingestion_worker, "_retry_or_fail", retry_or_fail)
    monkeypatch.setattr(
        ingestion_worker.time,
        "sleep",
        lambda _seconds: (_ for _ in ()).throw(StopLoop()),
    )

    with pytest.raises(StopLoop):
        ingestion_worker.worker_loop(idle_tracker=tracker)

    assert tracker.started == 1
    assert tracker.finished == 1
    if outcome in {"retryable", "unexpected"}:
        assert len(retried_errors) == 1
        assert job.lease_expires_at is retry_lease
    else:
        assert retried_errors == []


def test_main_returns_after_intentional_idle_exit(monkeypatch):
    worker_calls: list[str] = []
    monkeypatch.setattr(
        ingestion_worker,
        "worker_loop",
        lambda: worker_calls.append("idle-exit"),
    )
    monkeypatch.setattr(
        ingestion_worker.time,
        "sleep",
        lambda _seconds: pytest.fail("normal idle exit must not restart"),
    )

    ingestion_worker.main()

    assert worker_calls == ["idle-exit"]


def test_main_restarts_after_worker_exception(monkeypatch):
    worker_calls = 0
    sleep_calls: list[int] = []

    def worker_loop() -> None:
        nonlocal worker_calls
        worker_calls += 1
        if worker_calls == 1:
            raise RuntimeError("boom")

    monkeypatch.setattr(ingestion_worker, "worker_loop", worker_loop)
    monkeypatch.setattr(
        ingestion_worker.time,
        "sleep",
        lambda seconds: sleep_calls.append(seconds),
    )

    ingestion_worker.main()

    assert worker_calls == 2
    assert sleep_calls == [2]


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


def test_retryable_website_transcript_error_does_not_report_sentry_before_final_failure(
    test_db, monkeypatch
):
    website_id = uuid4()
    file_id = uuid4()
    _make_youtube_website_transcript_ingested_file(test_db, file_id, website_id)
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="extracting",
        attempts=0,
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    sentry_messages: list[str] = []
    status_updates: list[dict[str, str]] = []

    monkeypatch.setattr(
        ingestion_worker.sentry_sdk,
        "capture_message",
        lambda message, *, level=None: sentry_messages.append(f"{level}:{message}"),
    )

    def fake_update_transcript_status(
        _db, *, user_id, website_id, youtube_url, status, file_id=None, error=None
    ):
        status_updates.append(
            {
                "user_id": user_id,
                "website_id": str(website_id),
                "youtube_url": youtube_url,
                "status": status,
                "file_id": str(file_id) if file_id else "",
                "error": error or "",
            }
        )

    monkeypatch.setattr(
        WebsiteTranscriptService,
        "update_transcript_status",
        fake_update_transcript_status,
    )

    error = ingestion_worker.IngestionError(
        "VIDEO_DOWNLOAD_TEMPORARY", "temporary youtube failure", retryable=True
    )

    ingestion_worker._retry_or_fail(test_db, job, error)

    test_db.refresh(job)
    assert job.status == "queued"
    assert sentry_messages == []
    assert status_updates == []


def test_final_website_transcript_failure_reports_sentry_once(test_db, monkeypatch):
    website_id = uuid4()
    file_id = uuid4()
    record = _make_youtube_website_transcript_ingested_file(
        test_db, file_id, website_id
    )
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="extracting",
        attempts=ingestion_worker.MAX_ATTEMPTS - 1,
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    sentry_messages: list[dict[str, str]] = []
    status_updates: list[dict[str, str]] = []
    soft_deleted_file_ids: list[str] = []
    tags: dict[str, str] = {}
    extras: dict[str, str] = {}
    user_context: dict[str, str] = {}
    fingerprint: list[str] = []
    warning_logs: list[str] = []
    error_logs: list[str] = []

    class _Scope:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def set_tag(self, key, value):
            tags[key] = str(value)

        def set_extra(self, key, value):
            extras[key] = str(value)

        def set_user(self, value):
            user_context.clear()
            user_context.update(value)

        @property
        def fingerprint(self):
            return fingerprint

        @fingerprint.setter
        def fingerprint(self, value):
            fingerprint[:] = [str(item) for item in value]

    monkeypatch.setattr(ingestion_worker.sentry_sdk, "new_scope", lambda: _Scope())
    monkeypatch.setattr(
        ingestion_worker.sentry_sdk,
        "push_scope",
        lambda: pytest.fail("push_scope should not be used"),
    )
    monkeypatch.setattr(
        ingestion_worker.sentry_sdk,
        "capture_message",
        lambda message, *, level=None: sentry_messages.append(
            {"message": message, "level": str(level)}
        ),
    )
    monkeypatch.setattr(
        ingestion_worker.logger,
        "warning",
        lambda message, *args: warning_logs.append(message % args if args else message),
    )
    monkeypatch.setattr(
        ingestion_worker.logger,
        "error",
        lambda message, *args: error_logs.append(message % args if args else message),
    )

    def fake_update_transcript_status(
        _db, *, user_id, website_id, youtube_url, status, file_id=None, error=None
    ):
        status_updates.append(
            {
                "user_id": user_id,
                "website_id": str(website_id),
                "youtube_url": youtube_url,
                "status": status,
                "file_id": str(file_id) if file_id else "",
                "error": error or "",
            }
        )

    monkeypatch.setattr(
        WebsiteTranscriptService,
        "update_transcript_status",
        fake_update_transcript_status,
    )
    monkeypatch.setattr(
        FileIngestionService,
        "soft_delete_file",
        lambda _db, target_file_id: soft_deleted_file_ids.append(str(target_file_id)),
    )

    error = ingestion_worker.IngestionError(
        "VIDEO_DOWNLOAD_FORBIDDEN", "youtube blocked download", retryable=True
    )

    ingestion_worker._retry_or_fail(test_db, job, error)

    test_db.refresh(job)
    assert job.status == "failed"
    assert status_updates == [
        {
            "user_id": "test-user",
            "website_id": str(website_id),
            "youtube_url": "https://www.youtube.com/watch?v=abc123",
            "status": "failed",
            "file_id": str(file_id),
            "error": "youtube blocked download",
        }
    ]
    assert soft_deleted_file_ids == [str(record.id)]
    assert sentry_messages == [
        {
            "message": "Website YouTube transcript failed",
            "level": "error",
        }
    ]
    assert tags["ingestion_kind"] == "website_youtube_transcript"
    assert tags["ingestion_failure_code"] == "VIDEO_DOWNLOAD_FORBIDDEN"
    assert tags["ingestion_failure_stage"] == "extracting"
    assert extras["youtube_url"] == "https://www.youtube.com/watch?v=abc123"
    assert extras["website_id"] == str(website_id)
    assert extras["file_id"] == str(file_id)
    assert user_context == {"id": "test-user"}
    assert fingerprint == [
        "website-youtube-transcript-failed",
        "VIDEO_DOWNLOAD_FORBIDDEN",
    ]
    assert any(message.startswith("Job failed file_id=") for message in warning_logs)
    assert error_logs == []


def test_initialize_worker_sentry_uses_backend_settings(monkeypatch):
    init_calls: list[dict[str, object]] = []

    monkeypatch.setattr(
        ingestion_worker.settings, "sentry_dsn", "https://example@sentry.io/123"
    )
    monkeypatch.setattr(ingestion_worker.settings, "sentry_traces_sample_rate", 0.25)
    monkeypatch.setattr(ingestion_worker.settings, "sentry_profiles_sample_rate", 0.5)
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "production")
    monkeypatch.setattr(
        ingestion_worker.sentry_sdk, "init", lambda **kwargs: init_calls.append(kwargs)
    )
    monkeypatch.setattr(ingestion_worker, "_worker_sentry_initialized", False)

    ingestion_worker._initialize_worker_sentry()

    assert len(init_calls) == 1
    assert init_calls[0]["dsn"] == "https://example@sentry.io/123"
    assert init_calls[0]["traces_sample_rate"] == 0.25
    assert init_calls[0]["profiles_sample_rate"] == 0.5
    assert init_calls[0]["environment"] == "production"


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
    assert not ingestion_worker._is_allowed_file("text/xml", "settings.plist")


def test_process_youtube_job_disables_transcript_upload(test_db, monkeypatch, tmp_path):
    file_id = uuid4()
    record = _make_youtube_ingested_file(test_db, file_id)
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="queued",
        attempts=0,
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    upload_flags: list[bool] = []
    output_names: list[str] = []
    downloaded_media = tmp_path / "source.m4a"
    downloaded_media.write_bytes(b"youtube-audio")

    def fake_transcribe(_record, *, upload_transcript=True, output_name="ai.md"):
        upload_flags.append(upload_transcript)
        output_names.append(output_name)
        return "Transcript", {
            "title": "Test Video",
            "download_local_path": str(downloaded_media),
            "download_mime": "audio/mp4",
        }

    monkeypatch.setattr(ingestion_worker, "_transcribe_youtube", fake_transcribe)
    monkeypatch.setattr(
        ingestion_worker,
        "_write_derivatives_atomically",
        lambda *_args, **_kwargs: None,
    )

    ingestion_worker._process_youtube_job(test_db, job, record)

    assert upload_flags == [False]
    assert output_names == ["ai.md"]
    persisted_kinds = {
        item.kind
        for item in test_db.query(FileDerivative).filter(
            FileDerivative.file_id == file_id
        )
    }
    assert "source_original" in persisted_kinds
    assert "ai_md" in persisted_kinds
    test_db.refresh(record)
    assert "download_local_path" not in (record.source_metadata or {})
    assert "download_mime" not in (record.source_metadata or {})


def test_build_source_original_payload_uses_original_extension():
    record = IngestedFile(
        id=uuid4(),
        user_id="test-user",
        filename_original="slides.pptx",
        mime_original="application/vnd.openxmlformats-officedocument.presentationml.presentation",
        size_bytes=123,
        sha256="abc123",
        created_at=datetime.now(UTC),
    )

    payload = ingestion_worker._build_source_original_payload(
        record,
        content=b"source",
        mime="application/vnd.openxmlformats-officedocument.presentationml.presentation",
    )

    assert payload.kind == "source_original"
    assert payload.storage_key.endswith("/derivatives/source.pptx")


def test_process_youtube_website_transcript_uses_minimal_stages(test_db, monkeypatch):
    file_id = uuid4()
    website_id = uuid4()
    record = _make_youtube_website_transcript_ingested_file(
        test_db, file_id, website_id
    )
    job = FileProcessingJob(
        file_id=file_id,
        status="processing",
        stage="queued",
        attempts=0,
        updated_at=datetime.now(UTC),
    )
    test_db.add(job)
    test_db.commit()

    stages: list[str] = []
    output_names: list[str] = []

    def fake_set_stage(_db, _job, stage):
        stages.append(stage)

    def fake_transcribe(_record, *, upload_transcript=True, output_name="ai.md"):
        _ = upload_transcript
        output_names.append(output_name)
        return "Transcript", {"title": "Test Video"}

    monkeypatch.setattr(ingestion_worker, "_set_stage", fake_set_stage)
    monkeypatch.setattr(
        ingestion_worker, "_refresh_lease", lambda *_args, **_kwargs: None
    )
    monkeypatch.setattr(ingestion_worker, "_transcribe_youtube", fake_transcribe)
    monkeypatch.setattr(
        WebsiteTranscriptService,
        "update_transcript_status",
        lambda *_args, **_kwargs: None,
    )
    monkeypatch.setattr(
        WebsiteTranscriptService,
        "append_transcript_from_text",
        lambda *_args, **_kwargs: "",
    )
    monkeypatch.setattr(
        FileIngestionService,
        "soft_delete_file",
        lambda *_args, **_kwargs: None,
    )

    ingestion_worker._process_youtube_job(test_db, job, record)

    assert stages == ["validating", "extracting", "finalizing"]
    assert output_names == ["transcript.md"]


def test_transcribe_youtube_sign_in_required_is_non_retryable(test_db, monkeypatch):
    file_id = uuid4()
    record = _make_youtube_ingested_file(test_db, file_id)

    def fake_transcriber(*_args, **_kwargs):
        raise RuntimeError("Sign in to confirm you're not a bot")

    monkeypatch.setattr(
        ingestion_worker, "_load_youtube_transcriber", lambda: fake_transcriber
    )

    with pytest.raises(ingestion_worker.IngestionError) as exc_info:
        ingestion_worker._transcribe_youtube(record, upload_transcript=False)

    assert exc_info.value.code == "VIDEO_DOWNLOAD_FORBIDDEN"
    assert exc_info.value.retryable is False


def test_transcribe_youtube_blocked_anonymous_download_is_non_retryable(
    test_db, monkeypatch
):
    file_id = uuid4()
    record = _make_youtube_ingested_file(test_db, file_id)
    error_logs: list[str] = []

    def fake_transcriber(*_args, **_kwargs):
        raise RuntimeError("YouTube blocked anonymous download for this video")

    monkeypatch.setattr(
        ingestion_worker, "_load_youtube_transcriber", lambda: fake_transcriber
    )
    monkeypatch.setattr(
        ingestion_worker.logger,
        "error",
        lambda message, *args: error_logs.append(message % args if args else message),
    )

    with pytest.raises(ingestion_worker.IngestionError) as exc_info:
        ingestion_worker._transcribe_youtube(record, upload_transcript=False)

    assert exc_info.value.code == "VIDEO_DOWNLOAD_FORBIDDEN"
    assert exc_info.value.retryable is False
    assert error_logs == []


def test_classify_unexpected_error_maps_storage_tls_failure():
    error = RuntimeError(
        "SSL validation failed for "
        "https://example.r2.cloudflarestorage.com/sidebar/user/files/file/staging/source "
        "[SSL: CERTIFICATE_VERIFY_FAILED] certificate verify failed: self-signed "
        "certificate in certificate chain"
    )

    classified = ingestion_worker._classify_unexpected_error(error)

    assert classified.code == "STORAGE_TLS_FAILED"
    assert classified.retryable is False


def test_classify_unexpected_error_maps_storage_timeout_as_retryable():
    error = RuntimeError(
        "Read timeout on endpoint URL: "
        '"https://example.r2.cloudflarestorage.com/sidebar/user/files/file/derivatives/source.txt"'
    )

    classified = ingestion_worker._classify_unexpected_error(error)

    assert classified.code == "STORAGE_UNAVAILABLE"
    assert classified.retryable is True


def test_classify_unexpected_error_defaults_to_unknown():
    classified = ingestion_worker._classify_unexpected_error(RuntimeError("boom"))

    assert classified.code == "UNKNOWN_ERROR"
    assert classified.retryable is True


def test_resolve_worker_user_id_prefers_explicit_env(monkeypatch):
    monkeypatch.setenv("INGESTION_WORKER_USER_ID", "worker-user")
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "production")
    monkeypatch.setenv("TEST_USER_ID", "fallback-user")

    assert ingestion_worker._resolve_worker_user_id() == "worker-user"


def test_resolve_worker_user_id_uses_default_in_local(monkeypatch, tmp_path):
    monkeypatch.delenv("INGESTION_WORKER_USER_ID", raising=False)
    monkeypatch.setenv(
        "INGESTION_ACTIVE_USER_FILE", str(tmp_path / "missing-active-user-id.txt")
    )
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "local")
    monkeypatch.setenv("TEST_USER_ID", "fallback-user")

    assert ingestion_worker._resolve_worker_user_id() == "fallback-user"


def test_resolve_worker_user_id_prefers_active_user_file_in_local(
    monkeypatch, tmp_path
):
    active_user_file = tmp_path / "active-user-id.txt"
    active_user_file.write_text("jwt-user-id", encoding="utf-8")
    monkeypatch.delenv("INGESTION_WORKER_USER_ID", raising=False)
    monkeypatch.setenv("INGESTION_ACTIVE_USER_FILE", str(active_user_file))
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "local")
    monkeypatch.setenv("TEST_USER_ID", "fallback-user")

    assert ingestion_worker._resolve_worker_user_id() == "jwt-user-id"


def test_resolve_worker_user_id_is_unscoped_in_production(monkeypatch):
    monkeypatch.delenv("INGESTION_WORKER_USER_ID", raising=False)
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "production")
    monkeypatch.setenv("TEST_USER_ID", "fallback-user")

    assert ingestion_worker._resolve_worker_user_id() is None


def test_resolve_worker_user_id_is_unscoped_when_app_env_missing(monkeypatch):
    monkeypatch.delenv("INGESTION_WORKER_USER_ID", raising=False)
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "")
    monkeypatch.setenv("TEST_USER_ID", "fallback-user")

    assert ingestion_worker._resolve_worker_user_id() is None


def test_set_worker_claim_scope_sets_explicit_user(monkeypatch):
    scoped_to: list[str] = []

    def fake_set_session_user_id(_db, user_id):
        scoped_to.append(user_id)

    monkeypatch.setattr(
        ingestion_worker, "set_session_user_id", fake_set_session_user_id
    )

    session = _DummySession()
    ingestion_worker._set_worker_claim_scope(session, "user-1")

    assert scoped_to == ["user-1"]
    assert session.executed
    assert "set_config('app.ingestion_scope', '', false)" in session.executed[0].lower()


def test_set_worker_claim_scope_clears_stale_user_when_unscoped():
    session = _DummySession()
    session.info["app_user_id"] = "stale-user"

    ingestion_worker._set_worker_claim_scope(session, None)

    assert "app_user_id" not in session.info
    assert len(session.executed) == 2
    assert "set_config('app.user_id', '', false)" in session.executed[0].lower()
    assert (
        "set_config('app.ingestion_scope', 'all', false)" in session.executed[1].lower()
    )


def test_enforce_safe_dev_worker_configuration_allows_local_db(monkeypatch):
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "local")
    monkeypatch.setattr(
        ingestion_worker.settings,
        "database_url",
        "postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test",
    )

    ingestion_worker._enforce_safe_dev_worker_configuration(None)


def test_enforce_safe_dev_worker_configuration_blocks_remote_db(monkeypatch):
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "local")
    monkeypatch.setattr(
        ingestion_worker.settings,
        "database_url",
        "postgresql://user:pass@aws-1-eu-central-1.pooler.supabase.com:6543/postgres",
    )

    with pytest.raises(RuntimeError, match="Refusing to start ingestion worker"):
        ingestion_worker._enforce_safe_dev_worker_configuration(None)


def test_enforce_safe_dev_worker_configuration_allows_remote_db_scoped_worker(
    monkeypatch,
):
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "development")
    monkeypatch.setattr(
        ingestion_worker.settings,
        "database_url",
        "postgresql://user:pass@aws-1-eu-central-1.pooler.supabase.com:6543/postgres",
    )

    ingestion_worker._enforce_safe_dev_worker_configuration("fallback-user")


def test_enforce_safe_dev_worker_configuration_skips_production(monkeypatch):
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "production")
    monkeypatch.setattr(
        ingestion_worker.settings,
        "database_url",
        "postgresql://user:pass@aws-1-eu-central-1.pooler.supabase.com:6543/postgres",
    )

    ingestion_worker._enforce_safe_dev_worker_configuration(None)
