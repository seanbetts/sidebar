"""Health-oriented transitions for website processing jobs."""

from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta

import sentry_sdk
from sqlalchemy.orm import Session

from api.models.website_processing_job import WebsiteProcessingJob

logger = logging.getLogger(__name__)


class WebsiteJobHealthService:
    """Applies health-driven transitions for website save jobs."""

    _WORKER_UNAVAILABLE_MESSAGE = (
        "Website processing is temporarily unavailable. Please retry in a few minutes."
    )

    @staticmethod
    def fail_stale_queued_jobs_when_worker_unavailable(
        db: Session,
        user_id: str,
        *,
        queued_ttl_seconds: int = 120,
        worker_heartbeat_ttl_seconds: int = 45,
    ) -> int:
        """Fail stale queued jobs when no live website worker heartbeat is observed."""
        now = datetime.now(UTC)
        queued_ttl_seconds = max(1, queued_ttl_seconds)
        worker_heartbeat_ttl_seconds = max(1, worker_heartbeat_ttl_seconds)

        heartbeat_cutoff = now - timedelta(seconds=worker_heartbeat_ttl_seconds)
        has_recent_processing = (
            db.query(WebsiteProcessingJob.id)
            .filter(
                WebsiteProcessingJob.status == "processing",
                WebsiteProcessingJob.updated_at >= heartbeat_cutoff,
            )
            .first()
            is not None
        )
        if has_recent_processing:
            return 0

        queued_cutoff = now - timedelta(seconds=queued_ttl_seconds)
        stale_jobs = (
            db.query(WebsiteProcessingJob)
            .filter(
                WebsiteProcessingJob.user_id == user_id,
                WebsiteProcessingJob.status == "queued",
                WebsiteProcessingJob.updated_at <= queued_cutoff,
            )
            .all()
        )
        if not stale_jobs:
            return 0

        for job in stale_jobs:
            job.status = "failed"
            job.error_message = WebsiteJobHealthService._WORKER_UNAVAILABLE_MESSAGE
            job.lease_expires_at = None
            job.worker_id = None
            job.updated_at = now
        db.commit()
        logger.error(
            "Website worker unavailable for user_id=%s; failing %s stale queued jobs",
            user_id,
            len(stale_jobs),
        )
        sentry_sdk.capture_message(
            "Website worker unavailable for stale queued jobs", level="error"
        )
        return len(stale_jobs)
