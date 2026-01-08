"""Note model for markdown notes stored in Postgres."""

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime, Index, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class Note(Base):
    """Note model with markdown content and JSONB metadata."""

    __tablename__ = "notes"
    __table_args__ = (
        Index("idx_notes_user_last_opened", "user_id", "last_opened_at"),
        Index(
            "idx_notes_user_deleted_opened", "user_id", "deleted_at", "last_opened_at"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False, index=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    metadata_: Mapped[dict[str, Any]] = mapped_column(
        "metadata", JSONB, nullable=False, default=dict
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    last_opened_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    def __repr__(self):
        """Return a readable representation for debugging."""
        return f"<Note(id={self.id}, title='{self.title}')>"
