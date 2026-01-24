"""Task project model."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.db.base import Base

if TYPE_CHECKING:
    from api.models.task import Task
    from api.models.task_group import TaskGroup


class TaskProject(Base):
    """Project grouping for tasks."""

    __tablename__ = "task_projects"
    __table_args__ = (
        UniqueConstraint("user_id", "source_id", name="uq_task_projects_user_source"),
        Index("idx_task_projects_user_id", "user_id"),
        Index("idx_task_projects_group_id", "group_id"),
        Index("idx_task_projects_status", "status"),
        Index("idx_task_projects_deleted_at", "deleted_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    source_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    group_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("task_groups.id"), nullable=True
    )
    title: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="active")
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    group: Mapped[TaskGroup | None] = relationship(
        "TaskGroup", back_populates="projects"
    )
    tasks: Mapped[list[Task]] = relationship("Task", back_populates="project")

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<TaskProject(id={self.id}, title='{self.title}')>"
