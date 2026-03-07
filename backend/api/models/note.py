"""Note model for semantic notes stored in Postgres."""

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, Index, Integer, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class Note(Base):
    """Note model with semantic document storage and derived projections."""

    __tablename__ = "notes"
    __table_args__ = (
        Index("idx_notes_user_folder", "user_id", "folder_path"),
        Index(
            "idx_notes_user_archived_updated",
            "user_id",
            "is_archived",
            "updated_at",
        ),
        Index("idx_notes_user_pinned_order", "user_id", "pinned", "pinned_order"),
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
    document: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    document_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    plain_text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    folder_path: Mapped[str] = mapped_column(Text, nullable=False, default="")
    pinned: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    pinned_order: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_folder_marker: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    is_archived: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
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
