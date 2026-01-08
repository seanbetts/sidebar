"""User memory model for persistent Claude memory."""

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class UserMemory(Base):
    """Per-user memory files stored as markdown content."""

    __tablename__ = "user_memories"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    path: Mapped[str] = mapped_column(Text, nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )

    __table_args__ = (
        UniqueConstraint("user_id", "path", name="uq_user_memories_user_id_path"),
        Index("idx_user_memories_user_id_path", "user_id", "path"),
    )

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<UserMemory(user_id={self.user_id}, path={self.path})>"
