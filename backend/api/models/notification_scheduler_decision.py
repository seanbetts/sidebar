"""Per-user scheduler eligibility and dispatch decisions for diagnostics."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class NotificationSchedulerDecision(Base):
    """Persist one scheduler decision for a user-visible diagnostic trail."""

    __tablename__ = "notification_scheduler_decisions"
    __table_args__ = (
        Index(
            "idx_notification_scheduler_decisions_user_created",
            "user_id",
            "created_at",
        ),
        Index(
            "idx_notification_scheduler_decisions_run_started",
            "run_started_at",
            "created_at",
        ),
        Index(
            "idx_notification_scheduler_decisions_reason_created",
            "decision_reason",
            "created_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    worker_name: Mapped[str] = mapped_column(Text, nullable=False)
    run_started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    notification_kind: Mapped[str] = mapped_column(Text, nullable=False)
    decision_stage: Mapped[str] = mapped_column(Text, nullable=False)
    decision_reason: Mapped[str] = mapped_column(Text, nullable=False)
    scheduled_time: Mapped[str | None] = mapped_column(Text, nullable=True)
    schedule_timezone: Mapped[str | None] = mapped_column(Text, nullable=True)
    local_now: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    detail: Mapped[str | None] = mapped_column(Text, nullable=True)
