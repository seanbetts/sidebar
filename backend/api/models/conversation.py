"""Conversation model with JSONB message storage."""
from sqlalchemy import Column, String, Boolean, Integer, DateTime, Text, Index
from sqlalchemy.dialects.postgresql import UUID, JSONB
from datetime import datetime, timezone
import uuid
from api.db.base import Base


class Conversation(Base):
    """Conversation model with messages stored as JSONB array."""

    __tablename__ = "conversations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(String(255), nullable=False, index=True)
    title = Column(String(500), nullable=False)
    title_generated = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True)
    is_archived = Column(Boolean, default=False)
    first_message = Column(Text)  # Preview of first message (first 100 chars)
    message_count = Column(Integer, default=0)

    # Messages stored as JSONB array
    # Each message: {"id": "uuid", "role": "user|assistant", "content": "...", "status": "...", "timestamp": "...", "toolCalls": [...], "error": "..."}
    messages = Column(JSONB, nullable=False, default=list)

    # Indexes for search
    # Note: GIN index on JSONB allows fast searching within messages
    # For title search, we'll use ILIKE in queries (simple and effective)
    __table_args__ = (
        Index("idx_conversations_messages_gin", "messages", postgresql_using="gin"),
        Index("idx_conversations_user_updated_at", "user_id", "updated_at"),
    )

    def __repr__(self):
        """Return a readable representation for debugging."""
        return f"<Conversation(id={self.id}, title='{self.title}', message_count={self.message_count})>"
