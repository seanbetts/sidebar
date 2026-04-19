"""Cleanup helpers for failed plist sidecar uploads."""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from sqlalchemy.orm import Session

from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.services.file_ingestion_service import FileIngestionService

_UUID_PLIST_PATTERN = re.compile(
    r"^[0-9a-fA-F]{8}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{12}\.plist$"
)


@dataclass(frozen=True)
class PlistUploadCleanupCandidate:
    """A failed upload record that matches the plist-sidecar signature."""

    file_id: str
    user_id: str
    filename_original: str
    size_bytes: int
    updated_at: datetime | None


@dataclass(frozen=True)
class PlistUploadCleanupSummary:
    """Aggregate result for a plist-sidecar cleanup run."""

    dry_run: bool
    matched_files: int
    deleted_files: int
    matched_users: int


class PlistUploadCleanupService:
    """Find and clean failed plist uploads that match the sidecar pattern."""

    DEFAULT_MAX_SIZE_BYTES = 4 * 1024

    @staticmethod
    def find_candidates(
        db: Session,
        *,
        user_id: str | None = None,
        max_size_bytes: int = DEFAULT_MAX_SIZE_BYTES,
        limit: int | None = None,
    ) -> list[PlistUploadCleanupCandidate]:
        """Return candidate rows matching the accidental plist-sidecar signature."""
        query = (
            db.query(IngestedFile, FileProcessingJob)
            .join(FileProcessingJob, FileProcessingJob.file_id == IngestedFile.id)
            .filter(
                IngestedFile.deleted_at.is_(None),
                IngestedFile.mime_original == "application/octet-stream",
                IngestedFile.size_bytes <= max_size_bytes,
                FileProcessingJob.status == "failed",
                FileProcessingJob.error_code == "UNSUPPORTED_TYPE",
            )
            .order_by(FileProcessingJob.updated_at.asc(), IngestedFile.created_at.asc())
        )
        if user_id is not None:
            query = query.filter(IngestedFile.user_id == user_id)
        if limit is not None:
            query = query.limit(limit)

        candidates: list[PlistUploadCleanupCandidate] = []
        for record, job in query.all():
            if not PlistUploadCleanupService._is_uuid_plist(record.filename_original):
                continue
            candidates.append(
                PlistUploadCleanupCandidate(
                    file_id=str(record.id),
                    user_id=record.user_id,
                    filename_original=record.filename_original,
                    size_bytes=record.size_bytes,
                    updated_at=job.updated_at,
                )
            )
        return candidates

    @staticmethod
    def cleanup_candidates(
        db: Session,
        *,
        user_id: str | None = None,
        dry_run: bool = True,
        max_size_bytes: int = DEFAULT_MAX_SIZE_BYTES,
        limit: int | None = None,
    ) -> PlistUploadCleanupSummary:
        """Soft-delete matched plist-sidecar uploads when not in dry-run mode."""
        candidates = PlistUploadCleanupService.find_candidates(
            db,
            user_id=user_id,
            max_size_bytes=max_size_bytes,
            limit=limit,
        )
        deleted_files = 0
        if not dry_run:
            for candidate in candidates:
                deleted = FileIngestionService.delete_file(
                    db,
                    candidate.user_id,
                    UUID(candidate.file_id),
                    ensure_ready=False,
                )
                if deleted:
                    deleted_files += 1

        return PlistUploadCleanupSummary(
            dry_run=dry_run,
            matched_files=len(candidates),
            deleted_files=deleted_files,
            matched_users=len({candidate.user_id for candidate in candidates}),
        )

    @staticmethod
    def _is_uuid_plist(filename: str) -> bool:
        """Return whether the filename matches the accidental UUID plist pattern."""
        return bool(_UUID_PLIST_PATTERN.fullmatch(filename or ""))
