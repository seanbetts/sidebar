"""Task model for native task system."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import TYPE_CHECKING, Any

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.db.base import Base

if TYPE_CHECKING:
    from api.models.task_area import TaskArea
    from api.models.task_project import TaskProject


class Task(Base):
    """Task item supporting recurrence and scheduling."""

    __tablename__ = "tasks"
    __table_args__ = (
        UniqueConstraint("user_id", "source_id", name="uq_tasks_user_source"),
        Index("idx_tasks_user_id", "user_id"),
        Index("idx_tasks_project_id", "project_id"),
        Index("idx_tasks_area_id", "area_id"),
        Index("idx_tasks_status", "status"),
        Index("idx_tasks_deadline", "deadline"),
        Index("idx_tasks_completed_at", "completed_at"),
        Index("idx_tasks_next_instance_date", "next_instance_date"),
        Index("idx_tasks_deleted_at", "deleted_at"),
        Index("idx_tasks_repeat_template_id", "repeat_template_id"),
        Index("idx_tasks_user_status", "user_id", "status"),
        Index(
            "uq_tasks_repeat_template_deadline",
            "repeat_template_id",
            "deadline",
            unique=True,
            postgresql_where=text("repeat_template_id IS NOT NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    source_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("task_projects.id"), nullable=True
    )
    area_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("task_areas.id"), nullable=True
    )

    title: Mapped[str] = mapped_column(Text, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="inbox")

    deadline: Mapped[date | None] = mapped_column(Date, nullable=True)

    repeating: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    repeat_template: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    repeat_template_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("tasks.id"), nullable=True
    )

    recurrence_rule: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    next_instance_date: Mapped[date | None] = mapped_column(Date, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    trashed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    project: Mapped[TaskProject | None] = relationship(
        "TaskProject", back_populates="tasks"
    )
    area: Mapped[TaskArea | None] = relationship("TaskArea", back_populates="tasks")

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<Task(id={self.id}, title='{self.title}')>"
