"""Durable heartbeat state for the scheduled notification worker."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import DateTime, Integer, Text
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class NotificationSchedulerHeartbeat(Base):
    """Tracks the latest scheduled-notification worker loop status."""

    __tablename__ = "notification_scheduler_heartbeat"

    worker_name: Mapped[str] = mapped_column(Text, primary_key=True)
    last_started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_status: Mapped[str] = mapped_column(Text, nullable=False, default="idle")
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_task_reminders_due: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )
    last_task_reminders_dispatched: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )
    last_morning_digests_due: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )
    last_morning_digests_dispatched: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
