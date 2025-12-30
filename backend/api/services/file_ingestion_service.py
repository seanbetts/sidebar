"""Database helpers for file ingestion pipeline."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
import uuid

from sqlalchemy.orm import Session

from api.models.file_ingestion import IngestedFile, FileDerivative, FileProcessingJob


class FileIngestionService:
    """CRUD helpers for ingestion metadata."""

    @staticmethod
    def create_ingestion(
        db: Session,
        user_id: str,
        *,
        filename_original: str,
        mime_original: str,
        size_bytes: int,
        sha256: Optional[str] = None,
        file_id: Optional[uuid.UUID] = None,
    ) -> tuple[IngestedFile, FileProcessingJob]:
        """Create ingestion records for a new file upload."""
        now = datetime.now(timezone.utc)
        if file_id is None:
            file_id = uuid.uuid4()

        record = IngestedFile(
            id=file_id,
            user_id=user_id,
            filename_original=filename_original,
            mime_original=mime_original,
            size_bytes=size_bytes,
            sha256=sha256,
            created_at=now,
            deleted_at=None,
        )
        job = FileProcessingJob(
            file_id=file_id,
            status="queued",
            stage="queued",
            attempts=0,
            updated_at=now,
        )
        db.add(record)
        db.add(job)
        db.commit()
        return record, job

    @staticmethod
    def get_file(db: Session, user_id: str, file_id: uuid.UUID) -> Optional[IngestedFile]:
        """Fetch an ingested file record for a user."""
        return (
            db.query(IngestedFile)
            .filter(
                IngestedFile.id == file_id,
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
            )
            .first()
        )

    @staticmethod
    def get_job(db: Session, file_id: uuid.UUID) -> Optional[FileProcessingJob]:
        """Fetch the job record for a file."""
        return (
            db.query(FileProcessingJob)
            .filter(FileProcessingJob.file_id == file_id)
            .first()
        )

    @staticmethod
    def list_derivatives(db: Session, file_id: uuid.UUID) -> list[FileDerivative]:
        """List derivatives for a file."""
        return (
            db.query(FileDerivative)
            .filter(FileDerivative.file_id == file_id)
            .order_by(FileDerivative.created_at.asc())
            .all()
        )

    @staticmethod
    def delete_derivatives(db: Session, file_id: uuid.UUID) -> None:
        """Delete derivative records for a file."""
        db.query(FileDerivative).filter(FileDerivative.file_id == file_id).delete()
        db.commit()

    @staticmethod
    def get_derivative(
        db: Session,
        file_id: uuid.UUID,
        kind: str,
    ) -> Optional[FileDerivative]:
        """Fetch a derivative by kind."""
        return (
            db.query(FileDerivative)
            .filter(
                FileDerivative.file_id == file_id,
                FileDerivative.kind == kind,
            )
            .first()
        )

    @staticmethod
    def update_job_status(
        db: Session,
        file_id: uuid.UUID,
        *,
        status: str,
        stage: Optional[str] = None,
        error_code: Optional[str] = None,
        error_message: Optional[str] = None,
    ) -> Optional[FileProcessingJob]:
        """Update job status fields."""
        job = db.query(FileProcessingJob).filter(FileProcessingJob.file_id == file_id).first()
        if not job:
            return None
        job.status = status
        if stage is not None:
            job.stage = stage
        job.error_code = error_code
        job.error_message = error_message
        job.updated_at = datetime.now(timezone.utc)
        db.commit()
        return job

    @staticmethod
    def soft_delete_file(db: Session, file_id: uuid.UUID) -> Optional[IngestedFile]:
        """Mark an ingested file as deleted."""
        record = db.query(IngestedFile).filter(IngestedFile.id == file_id).first()
        if not record:
            return None
        record.deleted_at = datetime.now(timezone.utc)
        db.commit()
        return record
