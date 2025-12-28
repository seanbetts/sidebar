"""File metadata model for storage objects."""
from sqlalchemy import Column, DateTime, Text, BigInteger, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime, timezone
import uuid
from api.db.base import Base


class FileObject(Base):
    """File metadata for objects stored in R2/local storage."""

    __tablename__ = "files"
    __table_args__ = (
        UniqueConstraint("user_id", "path", name="uq_files_user_id_path"),
        Index("idx_files_user_id", "user_id"),
        Index("idx_files_user_id_path", "user_id", "path"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    path = Column(Text, nullable=False)
    bucket_key = Column(Text, nullable=False)
    size = Column(BigInteger, nullable=False, default=0)
    content_type = Column(Text, nullable=True)
    etag = Column(Text, nullable=True)
    category = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)

    def __repr__(self):
        """Return a readable representation for debugging."""
        return f"<FileObject(id={self.id}, path='{self.path}')>"
