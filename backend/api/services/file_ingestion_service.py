"""Database helpers for file ingestion pipeline."""

from __future__ import annotations

import shutil
import uuid
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import func
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.exceptions import ConflictError, InternalServerError
from api.models.file_ingestion import FileDerivative, FileProcessingJob, IngestedFile
from api.services.storage.service import get_storage_backend
from api.utils.pinned_order import lock_pinned_order

STAGING_ROOT = Path("/tmp/sidebar-ingestion")


class FileIngestionService:
    """CRUD helpers for ingestion metadata."""

    @staticmethod
    def create_ingestion(
        db: Session,
        user_id: str,
        *,
        filename_original: str,
        path: str | None = None,
        mime_original: str,
        size_bytes: int,
        sha256: str | None = None,
        source_url: str | None = None,
        source_metadata: dict | None = None,
        file_id: uuid.UUID | None = None,
    ) -> tuple[IngestedFile, FileProcessingJob]:
        """Create ingestion records for a new file upload."""
        now = datetime.now(UTC)
        if file_id is None:
            file_id = uuid.uuid4()
        else:
            existing = (
                db.query(IngestedFile)
                .filter(IngestedFile.id == file_id, IngestedFile.user_id == user_id)
                .first()
            )
            if existing:
                if existing.deleted_at is not None:
                    existing.deleted_at = None
                    existing.filename_original = filename_original
                    existing.path = path or existing.path
                    existing.mime_original = mime_original
                    existing.size_bytes = size_bytes
                    existing.sha256 = sha256
                    existing.source_url = source_url
                    if source_metadata is not None:
                        existing.source_metadata = source_metadata
                        flag_modified(existing, "source_metadata")
                    existing.updated_at = now
                    db.commit()
                job = FileIngestionService.get_job(db, file_id)
                if not job:
                    job = FileProcessingJob(
                        file_id=file_id,
                        status="queued",
                        stage="queued",
                        attempts=0,
                        updated_at=now,
                    )
                    db.add(job)
                    db.commit()
                return existing, job
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
            updated_at=now,
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
    def get_file(
        db: Session,
        user_id: str,
        file_id: uuid.UUID,
        *,
        include_deleted: bool = False,
    ) -> IngestedFile | None:
        """Fetch an ingested file record for a user."""
        query = db.query(IngestedFile).filter(
            IngestedFile.id == file_id,
            IngestedFile.user_id == user_id,
        )
        if not include_deleted:
            query = query.filter(IngestedFile.deleted_at.is_(None))
        return query.first()

    @staticmethod
    def get_job(db: Session, file_id: uuid.UUID) -> FileProcessingJob | None:
        """Fetch the job record for a file."""
        return (
            db.query(FileProcessingJob)
            .filter(FileProcessingJob.file_id == file_id)
            .first()
        )

    @staticmethod
    def list_ingestions(
        db: Session,
        user_id: str,
        *,
        limit: int | None = 50,
        include_deleted: bool = False,
        updated_after: datetime | None = None,
    ) -> list[IngestedFile]:
        """List ingested files for a user.

        Args:
            db: Database session.
            user_id: Current user ID.
            limit: Max records to return. Use None for no limit.
            include_deleted: Include soft-deleted records when True.
            updated_after: Filter records updated on/after this timestamp.

        Returns:
            List of ingested file records.
        """
        query = db.query(IngestedFile).filter(
            IngestedFile.user_id == user_id,
            func.coalesce(
                IngestedFile.source_metadata["website_transcript"].astext,
                "false",
            )
            != "true",
            ~func.coalesce(IngestedFile.path, "").ilike("%/ai/ai.md"),
        )
        if not include_deleted:
            query = query.filter(IngestedFile.deleted_at.is_(None))
        if updated_after is not None:
            query = query.filter(IngestedFile.updated_at >= updated_after)
            query = query.order_by(IngestedFile.updated_at.asc())
        else:
            query = query.order_by(IngestedFile.created_at.desc())
        if limit is not None:
            query = query.limit(limit)
        return query.all()

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
    ) -> FileDerivative | None:
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
        stage: str | None = None,
        error_code: str | None = None,
        error_message: str | None = None,
    ) -> FileProcessingJob | None:
        """Update job status fields."""
        job = (
            db.query(FileProcessingJob)
            .filter(FileProcessingJob.file_id == file_id)
            .first()
        )
        if not job:
            return None
        job.status = status
        if stage is not None:
            job.stage = stage
        job.error_code = error_code
        job.error_message = error_message
        job.updated_at = datetime.now(UTC)
        db.commit()
        return job

    @staticmethod
    def soft_delete_file(db: Session, file_id: uuid.UUID) -> IngestedFile | None:
        """Mark an ingested file as deleted."""
        record = db.query(IngestedFile).filter(IngestedFile.id == file_id).first()
        if not record:
            return None
        now = datetime.now(UTC)
        record.deleted_at = now
        record.updated_at = now
        db.commit()
        return record

    @staticmethod
    def update_pinned(
        db: Session,
        user_id: str,
        file_id: uuid.UUID,
        pinned: bool,
        *,
        client_updated_at: datetime | None = None,
    ) -> None:
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
        FileIngestionService._ensure_no_conflict(record, client_updated_at, op="pin")
        record.pinned = pinned
        if pinned:
            if record.pinned_order is None:
                lock_pinned_order(db, user_id, "ingested_files")
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
        record.updated_at = datetime.now(UTC)
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
                record.updated_at = datetime.now(UTC)
        db.commit()

    @staticmethod
    def update_filename(
        db: Session,
        user_id: str,
        file_id: uuid.UUID,
        filename: str,
        *,
        client_updated_at: datetime | None = None,
    ) -> None:
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
        FileIngestionService._ensure_no_conflict(record, client_updated_at, op="rename")
        record.filename_original = filename
        record.updated_at = datetime.now(UTC)
        db.commit()

    @staticmethod
    def delete_file(
        db: Session,
        user_id: str,
        file_id: uuid.UUID,
        *,
        allow_missing: bool = False,
        ensure_ready: bool = True,
        client_updated_at: datetime | None = None,
    ) -> bool:
        """Delete an ingested file and cleanup derivatives."""
        record = FileIngestionService.get_file(
            db, user_id, file_id, include_deleted=True
        )
        if not record:
            return allow_missing
        if record.deleted_at is not None:
            return True
        FileIngestionService._ensure_no_conflict(record, client_updated_at, op="delete")
        job = FileIngestionService.get_job(db, file_id)
        if ensure_ready and job and job.status not in {"ready", "failed", "canceled"}:
            raise ConflictError("File is still processing")

        derivatives = FileIngestionService.list_derivatives(db, file_id)
        storage = get_storage_backend()
        for derivative in derivatives:
            try:
                storage.delete_object(derivative.storage_key)
            except Exception as exc:
                raise InternalServerError("Failed to delete file data") from exc
        FileIngestionService.delete_derivatives(db, file_id)
        FileIngestionService.soft_delete_file(db, file_id)
        FileIngestionService._safe_cleanup(FileIngestionService._staging_path(file_id))
        return True

    @staticmethod
    def _ensure_no_conflict(
        record: IngestedFile,
        client_updated_at: datetime | None,
        *,
        op: str,
    ) -> None:
        if client_updated_at is None:
            return
        if record.updated_at and record.updated_at > client_updated_at:
            conflict = FileIngestionService._build_conflict_payload(
                record,
                op=op,
                client_updated_at=client_updated_at,
            )
            raise ConflictError(
                "File has been updated since last sync", {"conflict": conflict}
            )

    @staticmethod
    def _build_conflict_payload(
        record: IngestedFile,
        *,
        op: str | None,
        client_updated_at: datetime | None,
        operation_id: str | None = None,
        reason: str | None = None,
    ) -> dict[str, object]:
        return {
            "operationId": operation_id,
            "op": op,
            "id": str(record.id),
            "clientUpdatedAt": client_updated_at.isoformat()
            if client_updated_at
            else None,
            "serverUpdatedAt": record.updated_at.isoformat()
            if record.updated_at
            else None,
            "serverFile": FileIngestionService._file_sync_payload(record),
            "reason": reason,
        }

    @staticmethod
    def _file_sync_payload(record: IngestedFile) -> dict[str, object]:
        return {
            "id": str(record.id),
            "filename_original": record.filename_original,
            "path": record.path,
            "mime_original": record.mime_original,
            "size_bytes": record.size_bytes,
            "sha256": record.sha256,
            "source_url": record.source_url,
            "source_metadata": record.source_metadata,
            "pinned": record.pinned,
            "pinned_order": record.pinned_order,
            "created_at": record.created_at.isoformat() if record.created_at else None,
            "updated_at": record.updated_at.isoformat() if record.updated_at else None,
            "deleted_at": record.deleted_at.isoformat() if record.deleted_at else None,
        }

    @staticmethod
    def _staging_path(file_id: uuid.UUID) -> Path:
        return STAGING_ROOT / str(file_id) / "source"

    @staticmethod
    def _safe_cleanup(path: Path) -> None:
        if path.exists():
            shutil.rmtree(path.parent, ignore_errors=True)
