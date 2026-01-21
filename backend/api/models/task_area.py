"""Task area model."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, Index, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.db.base import Base

if TYPE_CHECKING:
    from api.models.task import Task
    from api.models.task_project import TaskProject


class TaskArea(Base):
    """Area grouping for tasks and projects."""

    __tablename__ = "task_areas"
    __table_args__ = (
        UniqueConstraint("user_id", "things_id", name="uq_task_areas_user_things"),
        Index("idx_task_areas_user_id", "user_id"),
        Index("idx_task_areas_deleted_at", "deleted_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    things_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    projects: Mapped[list[TaskProject]] = relationship(
        "TaskProject", back_populates="area"
    )
    tasks: Mapped[list[Task]] = relationship("Task", back_populates="area")

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<TaskArea(id={self.id}, title='{self.title}')>"
