"""Service helpers for website quick-save jobs."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.orm import Session

from api.config import settings
from api.models.website_processing_job import WebsiteProcessingJob


class WebsiteProcessingService:
    """CRUD helpers for website processing jobs."""

    _PROCESSING_STALLED_MESSAGE = "Website save stalled before completion. Try again."
    _QUEUED_STALLED_MESSAGE = "Website save is still waiting for a worker. Try again."

    @staticmethod
    def create_job(db: Session, user_id: str, url: str) -> WebsiteProcessingJob:
        """Create a new quick-save job."""
        now = datetime.now(UTC)
        job = WebsiteProcessingJob(
            user_id=user_id,
            url=url,
            status="queued",
            created_at=now,
            updated_at=now,
        )
        db.add(job)
        db.commit()
        db.refresh(job)
        return job

    @staticmethod
    def get_job(
        db: Session, user_id: str, job_id: uuid.UUID
    ) -> WebsiteProcessingJob | None:
        """Fetch a job by ID for a user."""
        return (
            db.query(WebsiteProcessingJob)
            .filter(
                WebsiteProcessingJob.id == job_id,
                WebsiteProcessingJob.user_id == user_id,
            )
            .first()
        )

    @staticmethod
    def update_job(
        db: Session,
        job_id: uuid.UUID,
        *,
        status: str,
        error_message: str | None = None,
        website_id: uuid.UUID | None = None,
    ) -> None:
        """Update job status and metadata."""
        job = (
            db.query(WebsiteProcessingJob)
            .filter(WebsiteProcessingJob.id == job_id)
            .first()
        )
        if not job:
            return
        if job.status == "canceled" and status != "canceled":
            return
        job.status = status
        job.error_message = error_message
        if website_id is not None:
            job.website_id = website_id
        if status in {"completed", "failed", "canceled"}:
            job.worker_id = None
            job.lease_expires_at = None
        job.updated_at = datetime.now(UTC)
        db.commit()

    @staticmethod
    def cancel_job(
        db: Session,
        user_id: str,
        job_id: uuid.UUID,
    ) -> WebsiteProcessingJob | None:
        """Cancel an active website processing job for a user."""
        job = WebsiteProcessingService.get_job(db, user_id, job_id)
        if not job:
            return None
        WebsiteProcessingService.update_job(db, job_id, status="canceled")
        db.refresh(job)
        return job

    @staticmethod
    def status_for_client(job: WebsiteProcessingJob) -> tuple[str, str | None]:
        """Return client-facing job status with stalled-job derivation."""
        now = datetime.now(UTC)

        if (
            job.status == "processing"
            and job.lease_expires_at is not None
            and job.lease_expires_at < now
        ):
            return "stalled", WebsiteProcessingService._PROCESSING_STALLED_MESSAGE

        queued_stall_seconds = max(
            settings.website_worker_lease_seconds,
            settings.website_save_timeout_seconds,
        )
        if (
            job.status == "queued"
            and (now - job.updated_at).total_seconds() > queued_stall_seconds
        ):
            return "stalled", WebsiteProcessingService._QUEUED_STALLED_MESSAGE

        if job.status == "failed":
            return "failed", job.error_message

        return job.status, None
