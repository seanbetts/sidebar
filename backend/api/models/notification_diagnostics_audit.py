"""Durable diagnostic audit rows for notification delivery attempts."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Integer, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class NotificationDiagnosticsAudit(Base):
    """Diagnostic audit trail for notification transport outcomes."""

    __tablename__ = "notification_diagnostics_audit"
    __table_args__ = (
        Index(
            "idx_notification_diagnostics_audit_user_created_at",
            "user_id",
            text("created_at DESC"),
        ),
        Index(
            "idx_notification_diagnostics_audit_installation_created_at",
            "installation_id",
            text("created_at DESC"),
        ),
        Index(
            "idx_notification_diagnostics_audit_kind_created_at",
            "notification_kind",
            text("created_at DESC"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    notification_kind: Mapped[str] = mapped_column(Text, nullable=False)
    installation_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    platform: Mapped[str | None] = mapped_column(Text, nullable=True)
    token_suffix: Mapped[str | None] = mapped_column(Text, nullable=True)
    apns_topic: Mapped[str | None] = mapped_column(Text, nullable=True)
    apns_env: Mapped[str | None] = mapped_column(Text, nullable=True)
    delivery_result: Mapped[str] = mapped_column(Text, nullable=False)
    skip_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    apns_status_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    apns_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
