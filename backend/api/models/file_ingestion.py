"""Models for file ingestion pipeline metadata."""
from datetime import datetime, timezone
import uuid

from sqlalchemy import Column, DateTime, Text, BigInteger, ForeignKey, Index, Boolean, Integer
from sqlalchemy.dialects.postgresql import UUID, JSONB

from api.db.base import Base


class IngestedFile(Base):
    """Canonical metadata for ingested files."""

    __tablename__ = "ingested_files"
    __table_args__ = (
        Index("idx_ingested_files_user_id", "user_id"),
        Index("idx_ingested_files_created_at", "created_at"),
        Index("idx_ingested_files_deleted_at", "deleted_at"),
        Index("idx_ingested_files_last_opened_at", "last_opened_at"),
        Index("idx_ingested_files_user_last_opened", "user_id", "last_opened_at"),
        Index("idx_ingested_files_path", "path"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    filename_original = Column(Text, nullable=False)
    path = Column(Text, nullable=True)
    mime_original = Column(Text, nullable=False)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    sha256 = Column(Text, nullable=True)
    source_url = Column(Text, nullable=True)
    source_metadata = Column(JSONB, nullable=True)
    pinned = Column(Boolean, nullable=False, default=False)
    pinned_order = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    last_opened_at = Column(DateTime(timezone=True), nullable=True, index=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)


class FileDerivative(Base):
    """Derivative artifact generated during ingestion."""

    __tablename__ = "file_derivatives"
    __table_args__ = (
        Index("idx_file_derivatives_file_id", "file_id"),
        Index("idx_file_derivatives_kind", "kind"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    file_id = Column(UUID(as_uuid=True), ForeignKey("ingested_files.id"), nullable=False)
    kind = Column(Text, nullable=False)
    storage_key = Column(Text, nullable=False)
    mime = Column(Text, nullable=False)
    size_bytes = Column(BigInteger, nullable=False, default=0)
    sha256 = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)


class FileProcessingJob(Base):
    """Processing job state for ingestion pipeline."""

    __tablename__ = "file_processing_jobs"
    __table_args__ = (
        Index("idx_file_processing_jobs_file_id", "file_id"),
        Index("idx_file_processing_jobs_status", "status"),
        Index("idx_file_processing_jobs_lease_expires_at", "lease_expires_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    file_id = Column(UUID(as_uuid=True), ForeignKey("ingested_files.id"), nullable=False)
    status = Column(Text, nullable=False, default="queued")
    stage = Column(Text, nullable=True)
    error_code = Column(Text, nullable=True)
    error_message = Column(Text, nullable=True)
    attempts = Column(BigInteger, nullable=False, default=0)
    started_at = Column(DateTime(timezone=True), nullable=True)
    finished_at = Column(DateTime(timezone=True), nullable=True)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    worker_id = Column(Text, nullable=True)
    lease_expires_at = Column(DateTime(timezone=True), nullable=True)
