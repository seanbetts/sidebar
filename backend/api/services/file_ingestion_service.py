"""Database helpers for file ingestion pipeline."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
import uuid

from sqlalchemy.orm import Session
from sqlalchemy import func

from api.models.file_ingestion import IngestedFile, FileDerivative, FileProcessingJob


class FileIngestionService:
    """CRUD helpers for ingestion metadata."""

    @staticmethod
    def create_ingestion(
        db: Session,
        user_id: str,
        *,
        filename_original: str,
        path: Optional[str] = None,
        mime_original: str,
        size_bytes: int,
        sha256: Optional[str] = None,
        source_url: Optional[str] = None,
        source_metadata: Optional[dict] = None,
        file_id: Optional[uuid.UUID] = None,
    ) -> tuple[IngestedFile, FileProcessingJob]:
        """Create ingestion records for a new file upload."""
        now = datetime.now(timezone.utc)
        if file_id is None:
            file_id = uuid.uuid4()
        path_value = path or filename_original

        record = IngestedFile(
            id=file_id,
            user_id=user_id,
            filename_original=filename_original,
            path=path_value,
            mime_original=mime_original,
            size_bytes=size_bytes,
            sha256=sha256,
            source_url=source_url,
            source_metadata=source_metadata,
            created_at=now,
            deleted_at=None,
        )
        db.add(record)
        db.flush()
        job = FileProcessingJob(
            file_id=file_id,
            status="queued",
            stage="queued",
            attempts=0,
            updated_at=now,
        )
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

    @staticmethod
    def update_pinned(db: Session, user_id: str, file_id: uuid.UUID, pinned: bool) -> None:
        """Update pinned state for a file."""
        record = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.id == file_id,
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
            )
            .first()
        )
        if not record:
            return
        record.pinned = pinned
        if pinned:
            if record.pinned_order is None:
                max_order = (
                    db.query(func.max(IngestedFile.pinned_order))
                    .filter(
                        IngestedFile.user_id == user_id,
                        IngestedFile.deleted_at.is_(None),
                        IngestedFile.pinned.is_(True),
                    )
                    .scalar()
                )
                record.pinned_order = (max_order if max_order is not None else -1) + 1
        else:
            record.pinned_order = None
        db.commit()

    @staticmethod
    def update_pinned_order(
        db: Session,
        user_id: str,
        ordered_ids: list[uuid.UUID],
    ) -> None:
        """Persist pinned order for a set of files."""
        if not ordered_ids:
            return
        order_map = {file_id: index for index, file_id in enumerate(ordered_ids)}
        records = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
                IngestedFile.id.in_(ordered_ids),
            )
            .all()
        )
        for record in records:
            if record.id in order_map:
                record.pinned_order = order_map[record.id]
                record.pinned = True
        db.commit()

    @staticmethod
    def update_filename(db: Session, user_id: str, file_id: uuid.UUID, filename: str) -> None:
        """Update filename for an ingested file."""
        record = (
            db.query(IngestedFile)
            .filter(
                IngestedFile.id == file_id,
                IngestedFile.user_id == user_id,
                IngestedFile.deleted_at.is_(None),
            )
            .first()
        )
        if not record:
            return
        record.filename_original = filename
        db.commit()
