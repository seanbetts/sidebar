"""Read-only inspection of durable worker queues."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime

from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from api.models.file_ingestion import FileProcessingJob, IngestedFile
from api.models.website_processing_job import WebsiteProcessingJob


@dataclass(frozen=True, slots=True)
class WorkerQueueDemand:
    """Whether each durable worker queue contains work that can be reclaimed."""

    website: bool
    ingestion: bool


class WorkerQueueDemandService:
    """Inspect durable queues without claiming, requeuing, or updating jobs."""

    @staticmethod
    def inspect(db: Session, *, now: datetime | None = None) -> WorkerQueueDemand:
        """Return demand for queued work and processing jobs with expired leases."""
        current_now = now or datetime.now(UTC)

        with db.no_autoflush:
            website_demand = (
                db.query(
                    db.query(WebsiteProcessingJob)
                    .filter(
                        or_(
                            and_(
                                WebsiteProcessingJob.status == "queued",
                                or_(
                                    WebsiteProcessingJob.lease_expires_at.is_(None),
                                    (
                                        WebsiteProcessingJob.lease_expires_at
                                        <= current_now
                                    ),
                                ),
                            ),
                            and_(
                                WebsiteProcessingJob.status == "processing",
                                WebsiteProcessingJob.lease_expires_at.is_not(None),
                                WebsiteProcessingJob.lease_expires_at < current_now,
                            ),
                        ),
                    )
                    .exists()
                ).scalar()
                is True
            )
            ingestion_demand = (
                db.query(
                    db.query(FileProcessingJob)
                    .join(IngestedFile, IngestedFile.id == FileProcessingJob.file_id)
                    .filter(
                        IngestedFile.deleted_at.is_(None),
                        or_(
                            and_(
                                FileProcessingJob.status == "queued",
                                or_(
                                    FileProcessingJob.lease_expires_at.is_(None),
                                    FileProcessingJob.lease_expires_at <= current_now,
                                ),
                            ),
                            and_(
                                FileProcessingJob.status == "processing",
                                FileProcessingJob.lease_expires_at.is_not(None),
                                FileProcessingJob.lease_expires_at < current_now,
                            ),
                        ),
                    )
                    .exists()
                ).scalar()
                is True
            )

        return WorkerQueueDemand(website=website_demand, ingestion=ingestion_demand)
