"""Website model for archived markdown content."""
from sqlalchemy import Column, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from datetime import datetime, timezone
import uuid
from api.db.base import Base


class Website(Base):
    """Website model with normalized URL and markdown content."""

    __tablename__ = "websites"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    url = Column(Text, nullable=False, unique=True)
    url_full = Column(Text, nullable=True)
    domain = Column(Text, nullable=False)
    title = Column(Text, nullable=False)
    content = Column(Text, nullable=False)
    source = Column(Text, nullable=True)
    saved_at = Column(DateTime(timezone=True), nullable=True)
    published_at = Column(DateTime(timezone=True), nullable=True)
    metadata_ = Column("metadata", JSONB, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    last_opened_at = Column(DateTime(timezone=True), nullable=True, index=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)

    def __repr__(self):
        return f"<Website(id={self.id}, url='{self.url}')>"
