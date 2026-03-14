from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from api.models.file_ingestion import FileDerivative, FileProcessingJob, IngestedFile
from workers import ingestion_worker


class _DummySession:
    def __init__(self):
        self.info: dict[str, str] = {}
        self.executed: list[str] = []

    def execute(self, statement):
        self.executed.append(str(statement))
        return None


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
        ingestion_worker.WebsiteTranscriptService,
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
    record = _make_youtube_website_transcript_ingested_file(test_db, file_id, website_id)
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

    class _Scope:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def set_tag(self, key, value):
            tags[key] = str(value)

        def set_extra(self, key, value):
            extras[key] = str(value)

        @property
        def user(self):
            return user_context

        @user.setter
        def user(self, value):
            user_context.clear()
            user_context.update(value)

        @property
        def fingerprint(self):
            return fingerprint

        @fingerprint.setter
        def fingerprint(self, value):
            fingerprint[:] = [str(item) for item in value]

    monkeypatch.setattr(ingestion_worker.sentry_sdk, "push_scope", lambda: _Scope())
    monkeypatch.setattr(
        ingestion_worker.sentry_sdk,
        "capture_message",
        lambda message, *, level=None: sentry_messages.append(
            {"message": message, "level": str(level)}
        ),
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
        ingestion_worker.WebsiteTranscriptService,
        "update_transcript_status",
        fake_update_transcript_status,
    )
    monkeypatch.setattr(
        ingestion_worker.FileIngestionService,
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


def test_initialize_worker_sentry_uses_backend_settings(monkeypatch):
    init_calls: list[dict[str, object]] = []

    monkeypatch.setattr(ingestion_worker.settings, "sentry_dsn", "https://example@sentry.io/123")
    monkeypatch.setattr(ingestion_worker.settings, "sentry_traces_sample_rate", 0.25)
    monkeypatch.setattr(ingestion_worker.settings, "sentry_profiles_sample_rate", 0.5)
    monkeypatch.setattr(ingestion_worker.settings, "app_env", "production")
    monkeypatch.setattr(ingestion_worker.sentry_sdk, "init", lambda **kwargs: init_calls.append(kwargs))
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


def test_process_youtube_job_disables_transcript_upload(
    test_db, monkeypatch, tmp_path
):
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
        ingestion_worker, "_write_derivatives_atomically", lambda *_args, **_kwargs: None
    )

    ingestion_worker._process_youtube_job(test_db, job, record)

    assert upload_flags == [False]
    assert output_names == ["ai.md"]
    persisted_kinds = {
        item.kind
        for item in test_db.query(FileDerivative).filter(FileDerivative.file_id == file_id)
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
    record = _make_youtube_website_transcript_ingested_file(test_db, file_id, website_id)
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
    monkeypatch.setattr(ingestion_worker, "_refresh_lease", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(ingestion_worker, "_transcribe_youtube", fake_transcribe)
    monkeypatch.setattr(
        ingestion_worker.WebsiteTranscriptService,
        "update_transcript_status",
        lambda *_args, **_kwargs: None,
    )
    monkeypatch.setattr(
        ingestion_worker.WebsiteTranscriptService,
        "append_transcript_from_text",
        lambda *_args, **_kwargs: "",
    )
    monkeypatch.setattr(
        ingestion_worker.FileIngestionService,
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
        "\"https://example.r2.cloudflarestorage.com/sidebar/user/files/file/derivatives/source.txt\""
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


def test_resolve_worker_user_id_prefers_active_user_file_in_local(monkeypatch, tmp_path):
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

    monkeypatch.setattr(ingestion_worker, "set_session_user_id", fake_set_session_user_id)

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
    assert "set_config('app.ingestion_scope', 'all', false)" in session.executed[1].lower()


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
