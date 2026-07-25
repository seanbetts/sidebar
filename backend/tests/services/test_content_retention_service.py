"""Tests for retention policy defaults and cleanup metrics."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from api import metrics
from api.models.file_ingestion import FileDerivative, IngestedFile
from api.models.task import Task
from api.models.task_operation_log import TaskOperationLog
from api.models.user_ai_provider_key import UserAIProviderKey
from api.models.website import Website
from api.models.website_processing_job import WebsiteProcessingJob
from api.services.content_retention_service import ContentRetentionService
from api.services.file_ingestion_service import FileIngestionService
from api.services.notes_document_types import note_document_from_plain_text
from api.services.notes_service import NotesService
from api.services.retention_policy import retention_policy_for
from api.services.task_service import TaskService
from api.services.user_ai_provider_key_service import UserAIProviderKeyService
from api.services.websites_service import WebsitesService


def test_retention_policy_defaults_match_design_doc() -> None:
    notes = retention_policy_for("notes")
    websites = retention_policy_for("websites")
    keys = retention_policy_for("user_ai_provider_keys")

    assert notes.full_retention_days == 7
    assert notes.total_retention_days == 90
    assert notes.degrade_payload is True
    assert websites.total_retention_days == 60
    assert keys.total_retention_days == 7
    assert keys.degrade_payload is False


def test_cleanup_metrics_exist() -> None:
    assert metrics.data_cleanup_actions_total is not None
    assert metrics.data_cleanup_duration_seconds is not None
    assert metrics.data_cleanup_backlog_age_seconds is not None


def test_prune_notes_tombstones_rows_after_restore_window(test_db) -> None:
    now = datetime.now(UTC)
    note = NotesService.create_note(
        test_db,
        "user-1",
        note_document_from_plain_text("# Keep Title\n\nLarge body"),
    )
    note.deleted_at = now - timedelta(days=8)
    note.updated_at = note.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_notes(test_db, now=now, limit=10)
    test_db.refresh(note)

    assert summary.tombstoned == 1
    assert note.payload_purged_at == now
    assert note.title == "# Keep Title"
    assert note.plain_text == ""
    assert note.document["blocks"][0]["type"] == "title"


def test_prune_websites_hard_deletes_rows_after_total_retention(test_db) -> None:
    now = datetime.now(UTC)
    website = WebsitesService.save_website(
        test_db,
        "user-1",
        url="https://example.com",
        title="Example",
        content="Large content body",
    )
    website.deleted_at = now - timedelta(days=61)
    website.updated_at = website.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_websites(test_db, now=now, limit=10)

    assert summary.hard_deleted == 1
    assert test_db.query(Website).filter(Website.id == website.id).one_or_none() is None


def test_prune_websites_tombstones_rows_after_restore_window(test_db) -> None:
    now = datetime.now(UTC)
    website = WebsitesService.save_website(
        test_db,
        "user-1",
        url="https://example.com/tombstone",
        title="Example",
        content="Large content body",
    )
    website.deleted_at = now - timedelta(days=8)
    website.updated_at = website.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_websites(test_db, now=now, limit=10)
    test_db.refresh(website)

    assert summary.tombstoned == 1
    assert website.payload_purged_at == now
    assert website.title == "Example"
    assert website.content == ""


def test_prune_ingested_files_removes_metadata_jobs_and_derivatives(test_db) -> None:
    now = datetime.now(UTC)
    record, _job = FileIngestionService.create_ingestion(
        test_db,
        "user-1",
        filename_original="report.pdf",
        path="report.pdf",
        mime_original="application/pdf",
        size_bytes=10,
    )
    derivative = FileDerivative(
        file_id=record.id,
        kind="viewer_pdf",
        storage_key="user-1/files/report/viewer.pdf",
        mime="application/pdf",
        size_bytes=10,
    )
    test_db.add(derivative)
    record.deleted_at = now - timedelta(days=31)
    record.updated_at = record.deleted_at
    test_db.commit()

    summary = ContentRetentionService.prune_ingested_files(test_db, now=now, limit=10)

    assert summary.hard_deleted == 1
    assert FileIngestionService.get_job(test_db, record.id) is None
    assert (
        test_db.query(IngestedFile).filter(IngestedFile.id == record.id).one_or_none()
        is None
    )


def test_prune_tasks_and_keys_hard_delete_after_retention(test_db) -> None:
    now = datetime.now(UTC)
    task = TaskService.create_task(test_db, "user-1", "Delete me")
    key = UserAIProviderKeyService.upsert_key(
        test_db,
        user_id="user-1",
        provider="openai",
        api_key="sk-openai-abcdef1234",
    )
    test_db.commit()

    TaskService.delete_task(test_db, "user-1", str(task.id))
    UserAIProviderKeyService.soft_delete_key(test_db, "user-1", "openai")
    task.deleted_at = now - timedelta(days=61)
    task.updated_at = task.deleted_at
    key.deleted_at = now - timedelta(days=8)
    key.updated_at = key.deleted_at
    test_db.commit()
    task_id = task.id

    task_summary = ContentRetentionService.prune_tasks(test_db, now=now, limit=10)
    key_summary = ContentRetentionService.prune_user_ai_provider_keys(
        test_db, now=now, limit=10
    )

    assert task_summary.hard_deleted == 1
    assert key_summary.hard_deleted == 1
    assert test_db.query(Task).filter(Task.id == task_id).one_or_none() is None
    assert (
        test_db.query(UserAIProviderKey)
        .filter(UserAIProviderKey.id == key.id)
        .one_or_none()
        is None
    )


def test_prune_tasks_hard_deletes_expired_recurring_series(test_db) -> None:
    now = datetime.now(UTC)
    template = TaskService.create_task(
        test_db,
        "user-1",
        "Recurring template",
        repeating=True,
        repeat_template=True,
    )
    template.repeat_template_id = template.id
    instance = TaskService.create_task(
        test_db,
        "user-1",
        "Recurring instance",
        repeating=True,
        repeat_template_id=str(template.id),
    )
    test_db.commit()

    TaskService.trash_task_series(test_db, "user-1", str(template.id))
    expired_at = now - timedelta(days=61)
    template.deleted_at = expired_at - timedelta(seconds=1)
    template.updated_at = template.deleted_at
    instance.deleted_at = expired_at
    instance.updated_at = expired_at
    test_db.commit()
    task_ids = [template.id, instance.id]

    summary = ContentRetentionService.prune_tasks(test_db, now=now, limit=10)

    assert summary.hard_deleted == 2
    assert test_db.query(Task).filter(Task.id.in_(task_ids)).count() == 0


def test_prune_operational_tables_deletes_stale_jobs_and_logs(test_db) -> None:
    now = datetime.now(UTC)
    website_job = WebsiteProcessingJob(
        user_id="user-1",
        url="https://example.com",
        status="failed",
        created_at=now - timedelta(days=8),
        updated_at=now - timedelta(days=8),
    )
    file_record, file_job = FileIngestionService.create_ingestion(
        test_db,
        "user-1",
        filename_original="ops.pdf",
        path="ops.pdf",
        mime_original="application/pdf",
        size_bytes=10,
    )
    file_job.status = "failed"
    file_job.updated_at = now - timedelta(days=8)
    log = TaskOperationLog(
        user_id="user-1",
        operation_id="op-1",
        operation_type="add",
        payload={},
        created_at=now - timedelta(days=15),
    )
    test_db.add_all([website_job, log])
    file_record.updated_at = now
    test_db.commit()

    summary = ContentRetentionService.prune_operational_tables(
        test_db, now=now, limit=50
    )

    assert summary["website_processing_jobs"].hard_deleted == 1
    assert summary["file_processing_jobs"].hard_deleted == 1
    assert summary["task_operation_log"].hard_deleted == 1
