"""Service helpers for website quick-save jobs."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy.orm import Session

from api.models.website_processing_job import WebsiteProcessingJob


class WebsiteProcessingService:
    """CRUD helpers for website processing jobs."""

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
        job.status = status
        job.error_message = error_message
        if website_id is not None:
            job.website_id = website_id
        job.updated_at = datetime.now(UTC)
        db.commit()
