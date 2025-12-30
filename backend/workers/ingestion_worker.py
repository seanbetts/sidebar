"""Ingestion worker loop with leasing and stage updates."""
from __future__ import annotations

import os
import time
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import and_, or_

from api.db.session import SessionLocal
from api.models.file_ingestion import FileProcessingJob


LEASE_SECONDS = 30
SLEEP_SECONDS = 2
PIPELINE_STAGES = [
    "validating",
    "converting",
    "extracting",
    "ai_md",
    "thumb",
    "finalizing",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _claim_job(db, worker_id: str) -> FileProcessingJob | None:
    job = (
        db.query(FileProcessingJob)
        .filter(
            and_(
                FileProcessingJob.status == "queued",
                or_(
                    FileProcessingJob.lease_expires_at.is_(None),
                    FileProcessingJob.lease_expires_at < _now(),
                ),
            )
        )
        .order_by(FileProcessingJob.updated_at.asc())
        .with_for_update(skip_locked=True)
        .first()
    )
    if not job:
        return None

    job.status = "processing"
    job.stage = "validating"
    job.worker_id = worker_id
    job.lease_expires_at = _now() + timedelta(seconds=LEASE_SECONDS)
    job.started_at = job.started_at or _now()
    job.updated_at = _now()
    db.commit()
    return job


def _refresh_lease(db, job: FileProcessingJob) -> None:
    job.lease_expires_at = _now() + timedelta(seconds=LEASE_SECONDS)
    job.updated_at = _now()
    db.commit()


def _set_stage(db, job: FileProcessingJob, stage: str) -> None:
    job.stage = stage
    job.updated_at = _now()
    db.commit()


def _mark_ready(db, job: FileProcessingJob) -> None:
    job.status = "ready"
    job.stage = "ready"
    job.finished_at = _now()
    job.updated_at = _now()
    db.commit()


def worker_loop() -> None:
    worker_id = os.getenv("INGESTION_WORKER_ID") or f"worker-{uuid4()}"
    while True:
        with SessionLocal() as db:
            job = _claim_job(db, worker_id)
            if not job:
                time.sleep(SLEEP_SECONDS)
                continue

            for stage in PIPELINE_STAGES:
                db.refresh(job)
                if job.status in {"paused", "canceled"}:
                    break
                _set_stage(db, job, stage)
                _refresh_lease(db, job)
                time.sleep(0.1)

            db.refresh(job)
            if job.status not in {"paused", "canceled"}:
                _mark_ready(db, job)


if __name__ == "__main__":
    worker_loop()
