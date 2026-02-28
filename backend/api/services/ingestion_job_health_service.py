"""Health-oriented transitions for ingestion jobs."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy.orm import Session

from api.models.file_ingestion import FileProcessingJob, IngestedFile


class IngestionJobHealthService:
    """Applies health-driven job state transitions."""

    @staticmethod
    def fail_stale_queued_jobs_when_worker_unavailable(
        db: Session,
        user_id: str,
        *,
        queued_ttl_seconds: int = 120,
        worker_heartbeat_ttl_seconds: int = 45,
    ) -> int:
        """Fail stale queued jobs when no worker heartbeat is observed."""
        now = datetime.now(UTC)
        queued_ttl_seconds = max(1, queued_ttl_seconds)
        worker_heartbeat_ttl_seconds = max(1, worker_heartbeat_ttl_seconds)

        heartbeat_cutoff = now - timedelta(seconds=worker_heartbeat_ttl_seconds)
        has_recent_processing = (
            db.query(FileProcessingJob.id)
            .filter(
                FileProcessingJob.status == "processing",
                FileProcessingJob.updated_at >= heartbeat_cutoff,
            )
            .first()
            is not None
        )
        if has_recent_processing:
            return 0

        queued_cutoff = now - timedelta(seconds=queued_ttl_seconds)
        stale_jobs = (
            db.query(FileProcessingJob)
            .join(IngestedFile, IngestedFile.id == FileProcessingJob.file_id)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                FileProcessingJob.status == "queued",
                FileProcessingJob.updated_at <= queued_cutoff,
            )
            .all()
        )
        if not stale_jobs:
            return 0

        for job in stale_jobs:
            job.status = "failed"
            job.stage = "failed"
            job.error_code = "INGESTION_WORKER_UNAVAILABLE"
            job.error_message = (
                "Processing is temporarily unavailable. "
                "Please retry in a few minutes."
            )
            job.finished_at = now
            job.lease_expires_at = None
            job.updated_at = now
        db.commit()
        return len(stale_jobs)
