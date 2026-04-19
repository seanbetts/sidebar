"""Tests for plist upload cleanup targeting."""

from __future__ import annotations

import pytest
from uuid import UUID

from api.services.file_ingestion_service import FileIngestionService
from api.services.plist_upload_cleanup_service import PlistUploadCleanupService


@pytest.fixture
def db_session(test_db):
    return test_db


def _create_failed_ingestion(
    db_session,
    *,
    user_id: str,
    filename: str,
    mime_original: str = "application/octet-stream",
    size_bytes: int = 512,
    error_code: str = "UNSUPPORTED_TYPE",
    status: str = "failed",
) -> str:
    record, _job = FileIngestionService.create_ingestion(
        db_session,
        user_id,
        filename_original=filename,
        path=filename,
        mime_original=mime_original,
        size_bytes=size_bytes,
    )
    FileIngestionService.update_job_status(
        db_session,
        record.id,
        status=status,
        stage=status,
        error_code=error_code,
        error_message="Unsupported file type",
    )
    return str(record.id)


def test_find_candidates_only_matches_small_uuid_named_plists(db_session) -> None:
    matching_id = _create_failed_ingestion(
        db_session,
        user_id="user-1",
        filename="0481BC53-E4E0-403F-976D-E5A11D13960B.plist",
    )
    _create_failed_ingestion(
        db_session,
        user_id="user-1",
        filename="settings.plist",
    )
    _create_failed_ingestion(
        db_session,
        user_id="user-1",
        filename="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.plist",
        size_bytes=8192,
    )
    _create_failed_ingestion(
        db_session,
        user_id="user-1",
        filename="report.pdf",
        mime_original="application/pdf",
    )
    _create_failed_ingestion(
        db_session,
        user_id="user-1",
        filename="11111111-2222-3333-4444-555555555555.plist",
        status="ready",
    )

    candidates = PlistUploadCleanupService.find_candidates(db_session)

    assert [candidate.file_id for candidate in candidates] == [matching_id]


def test_cleanup_soft_deletes_matching_candidates_and_respects_user_filter(
    db_session,
) -> None:
    user_one_id = _create_failed_ingestion(
        db_session,
        user_id="user-1",
        filename="0481BC53-E4E0-403F-976D-E5A11D13960B.plist",
    )
    user_two_id = _create_failed_ingestion(
        db_session,
        user_id="user-2",
        filename="58692B3D-606D-4187-90EC-443CC61B301C.plist",
    )

    summary = PlistUploadCleanupService.cleanup_candidates(
        db_session,
        user_id="user-1",
        dry_run=False,
    )

    deleted_record = FileIngestionService.get_file(
        db_session,
        "user-1",
        UUID(user_one_id),
        include_deleted=True,
    )
    retained_record = FileIngestionService.get_file(
        db_session,
        "user-2",
        UUID(user_two_id),
        include_deleted=True,
    )

    assert summary.matched_files == 1
    assert summary.deleted_files == 1
    assert summary.matched_users == 1
    assert deleted_record is not None
    assert deleted_record.deleted_at is not None
    assert retained_record is not None
    assert retained_record.deleted_at is None
