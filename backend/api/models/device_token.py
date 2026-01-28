"""Device token model for push notifications."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class DeviceToken(Base):
    """Device token used for push notification delivery."""

    __tablename__ = "device_tokens"
    __table_args__ = (
        UniqueConstraint("token", name="uq_device_tokens_token"),
        Index("idx_device_tokens_user_id", "user_id"),
        Index("idx_device_tokens_token", "token"),
        Index("idx_device_tokens_disabled_at", "disabled_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    token: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(Text, nullable=False)
    environment: Mapped[str] = mapped_column(Text, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), index=True
    )
    disabled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return (
            "<DeviceToken(id="
            f"{self.id}, user_id='{self.user_id}', platform='{self.platform}')>"
        )
