"""User memory model for persistent Claude memory."""
from datetime import datetime, timezone
import uuid

from sqlalchemy import Column, DateTime, Text, UniqueConstraint, Index
from sqlalchemy.dialects.postgresql import UUID

from api.db.base import Base


class UserMemory(Base):
    """Per-user memory files stored as markdown content."""

    __tablename__ = "user_memories"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False, index=True)
    path = Column(Text, nullable=False)
    content = Column(Text, nullable=False)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint("user_id", "path", name="uq_user_memories_user_id_path"),
        Index("idx_user_memories_user_id_path", "user_id", "path"),
    )

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<UserMemory(user_id={self.user_id}, path={self.path})>"
