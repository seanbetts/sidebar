"""Durable per-cycle history for the notification scheduler worker."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Integer, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class NotificationSchedulerRun(Base):
    """One persisted scheduler cycle for internal diagnostics and postmortems."""

    __tablename__ = "notification_scheduler_runs"
    __table_args__ = (
        Index("idx_notification_scheduler_runs_started_at", "started_at"),
        Index("idx_notification_scheduler_runs_created_at", "created_at"),
        Index("idx_notification_scheduler_runs_status", "status"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    worker_name: Mapped[str] = mapped_column(Text, nullable=False)
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    status: Mapped[str] = mapped_column(Text, nullable=False)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    task_reminders_due: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    task_reminders_dispatched: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )
    morning_digests_due: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    morning_digests_dispatched: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
