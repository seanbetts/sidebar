"""Note model for markdown notes stored in Postgres."""
from sqlalchemy import Column, DateTime, Text, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB
from datetime import datetime, timezone
import uuid
from api.db.base import Base


class Note(Base):
    """Note model with markdown content and JSONB metadata."""

    __tablename__ = "notes"
    __table_args__ = (
        Index("idx_notes_user_last_opened", "user_id", "last_opened_at"),
        Index("idx_notes_user_deleted_opened", "user_id", "deleted_at", "last_opened_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False, index=True)
    title = Column(Text, nullable=False)
    content = Column(Text, nullable=False)
    metadata_ = Column("metadata", JSONB, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    last_opened_at = Column(DateTime(timezone=True), nullable=True, index=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True, index=True)

    def __repr__(self):
        """Return a readable representation for debugging."""
        return f"<Note(id={self.id}, title='{self.title}')>"
