"""Task operation log for offline sync idempotency."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime, Index, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class TaskOperationLog(Base):
    """Idempotency record for applied task operations."""

    __tablename__ = "task_operation_log"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "operation_id", name="uq_task_operation_log_user_operation"
        ),
        Index("idx_task_operation_log_user_id", "user_id"),
        Index("idx_task_operation_log_operation_id", "operation_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    operation_id: Mapped[str] = mapped_column(Text, nullable=False)
    operation_type: Mapped[str] = mapped_column(Text, nullable=False)
    payload: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<TaskOperationLog(id={self.id}, operation_id='{self.operation_id}')>"
