"""Processing job tracking for website quick saves."""
from datetime import datetime, timezone
import uuid

from sqlalchemy import Column, DateTime, Text, Index, ForeignKey
from sqlalchemy.dialects.postgresql import UUID

from api.db.base import Base


class WebsiteProcessingJob(Base):
    """Track async website quick-save jobs."""

    __tablename__ = "website_processing_jobs"
    __table_args__ = (
        Index("idx_website_jobs_user_id", "user_id"),
        Index("idx_website_jobs_status", "status"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    url = Column(Text, nullable=False)
    status = Column(Text, nullable=False, default="queued")
    error_message = Column(Text, nullable=True)
    website_id = Column(UUID(as_uuid=True), ForeignKey("websites.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
