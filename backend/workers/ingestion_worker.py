"""Ingestion worker loop with leasing and stage updates."""
from __future__ import annotations

import os
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from hashlib import sha256
from pathlib import Path
import shutil
from uuid import uuid4

from sqlalchemy import and_, or_

from api.db.session import SessionLocal
from api.models.file_ingestion import FileProcessingJob, IngestedFile, FileDerivative
from api.services.storage.service import get_storage_backend


LEASE_SECONDS = 30
SLEEP_SECONDS = 2
MAX_ATTEMPTS = 3
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


@dataclass(frozen=True)
class DerivativePayload:
    kind: str
    storage_key: str
    mime: str
    size_bytes: int
    sha256: str | None
    content: bytes


class IngestionError(Exception):
    def __init__(self, code: str, message: str, retryable: bool = False):
        super().__init__(message)
        self.code = code
        self.retryable = retryable


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
    job.worker_id = None
    job.lease_expires_at = None
    db.commit()


def _retry_or_fail(db, job: FileProcessingJob, error: IngestionError) -> None:
    job.attempts = (job.attempts or 0) + 1
    job.error_code = error.code
    job.error_message = str(error)
    job.updated_at = _now()
    job.worker_id = None
    job.lease_expires_at = None

    if error.retryable and job.attempts < MAX_ATTEMPTS:
        job.status = "queued"
        db.commit()
        return

    job.status = "failed"
    job.finished_at = _now()
    db.commit()


def _get_file(db, job: FileProcessingJob) -> IngestedFile:
    record = db.query(IngestedFile).filter(IngestedFile.id == job.file_id).first()
    if not record:
        raise IngestionError("FILE_NOT_FOUND", "Ingestion record missing", retryable=False)
    return record


def _staging_path(file_id: str) -> Path:
    return Path("/tmp/sidebar-ingestion") / file_id / "source"


def _cleanup_staging(file_id: str) -> None:
    staging_root = Path("/tmp/sidebar-ingestion") / file_id
    if staging_root.exists():
        shutil.rmtree(staging_root, ignore_errors=True)


def _detect_extension(filename: str, mime: str) -> str:
    suffix = Path(filename).suffix
    if suffix:
        return suffix
    if mime == "image/png":
        return ".png"
    if mime in {"image/jpeg", "image/jpg"}:
        return ".jpg"
    return ""


def _build_derivatives(record: IngestedFile, source_path: Path) -> list[DerivativePayload]:
    mime = record.mime_original
    file_id = str(record.id)
    content = source_path.read_bytes()

    if mime == "application/pdf":
        viewer = DerivativePayload(
            kind="viewer_pdf",
            storage_key=f"files/{file_id}/derivatives/viewer.pdf",
            mime="application/pdf",
            size_bytes=len(content),
            sha256=sha256(content).hexdigest(),
            content=content,
        )
    elif mime.startswith("image/"):
        extension = _detect_extension(record.filename_original, mime)
        viewer = DerivativePayload(
            kind="image_original",
            storage_key=f"files/{file_id}/derivatives/image{extension or ''}",
            mime=mime,
            size_bytes=len(content),
            sha256=sha256(content).hexdigest(),
            content=content,
        )
    else:
        raise IngestionError("UNSUPPORTED_TYPE", "Unsupported file type", retryable=False)

    ai_body = (
        "---\n"
        f"file_id: {record.id}\n"
        f"source_filename: {record.filename_original}\n"
        f"source_mime: {record.mime_original}\n"
        f"created_at: {record.created_at.isoformat()}\n"
        f"sha256: {record.sha256}\n"
        "derivatives:\n"
        f"  {viewer.kind}: true\n"
        "---\n\n"
        "Content extraction is not yet available."
    )
    ai_bytes = ai_body.encode("utf-8")
    ai_md = DerivativePayload(
        kind="ai_md",
        storage_key=f"files/{file_id}/ai/ai.md",
        mime="text/markdown",
        size_bytes=len(ai_bytes),
        sha256=sha256(ai_bytes).hexdigest(),
        content=ai_bytes,
    )

    return [viewer, ai_md]


def worker_loop() -> None:
    worker_id = os.getenv("INGESTION_WORKER_ID") or f"worker-{uuid4()}"
    while True:
        with SessionLocal() as db:
            job = _claim_job(db, worker_id)
            if not job:
                time.sleep(SLEEP_SECONDS)
                continue

            try:
                record = _get_file(db, job)
                source_path = _staging_path(str(record.id))
                if not source_path.exists():
                    raise IngestionError("SOURCE_MISSING", "Uploaded file not found", retryable=False)

                for stage in PIPELINE_STAGES:
                    db.refresh(job)
                    if job.status in {"paused", "canceled"}:
                        raise IngestionError("JOB_HALTED", "Job halted by user", retryable=False)
                    _set_stage(db, job, stage)
                    _refresh_lease(db, job)

                    if stage == "validating":
                        if record.size_bytes <= 0:
                            raise IngestionError("FILE_EMPTY", "Uploaded file is empty", retryable=False)
                    elif stage in {"converting", "extracting", "ai_md", "thumb"}:
                        time.sleep(0.05)
                    elif stage == "finalizing":
                        derivatives = _build_derivatives(record, source_path)
                        storage = get_storage_backend()
                        for item in derivatives:
                            storage.put_object(item.storage_key, item.content, content_type=item.mime)

                        db.query(FileDerivative).filter(FileDerivative.file_id == record.id).delete()
                        now = _now()
                        for item in derivatives:
                            db.add(
                                FileDerivative(
                                    file_id=record.id,
                                    kind=item.kind,
                                    storage_key=item.storage_key,
                                    mime=item.mime,
                                    size_bytes=item.size_bytes,
                                    sha256=item.sha256,
                                    created_at=now,
                                )
                            )
                        db.commit()

                db.refresh(job)
                if job.status not in {"paused", "canceled"}:
                    _mark_ready(db, job)
                    _cleanup_staging(str(record.id))
            except IngestionError as error:
                if error.code == "JOB_HALTED":
                    continue
                _retry_or_fail(db, job, error)
                if job.status == "failed":
                    _cleanup_staging(str(job.file_id))
            except Exception as error:
                _retry_or_fail(db, job, IngestionError("UNKNOWN_ERROR", str(error), retryable=True))
                if job.status == "failed":
                    _cleanup_staging(str(job.file_id))


if __name__ == "__main__":
    worker_loop()
