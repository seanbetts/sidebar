"""Models for notification-capable app installations and user bindings."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Index, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class DeviceInstallation(Base):
    """A single app installation capable of receiving push notifications."""

    __tablename__ = "device_installations"
    __table_args__ = (
        Index(
            "uq_device_installations_active_installation_id",
            "installation_id",
            unique=True,
            postgresql_where=text("disabled_at IS NULL"),
        ),
        Index(
            "uq_device_installations_active_token",
            "token",
            unique=True,
            postgresql_where=text("disabled_at IS NULL"),
        ),
        Index("idx_device_installations_platform", "platform"),
        Index("idx_device_installations_environment", "environment"),
        Index("idx_device_installations_disabled_at", "disabled_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    installation_id: Mapped[str] = mapped_column(Text, nullable=False)
    token: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[str] = mapped_column(Text, nullable=False)
    environment: Mapped[str] = mapped_column(Text, nullable=False)
    capabilities: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )
    is_foreground: Mapped[bool] = mapped_column(nullable=False, default=False)
    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    disabled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class DeviceInstallationUser(Base):
    """Tracks which user is currently bound to an installation."""

    __tablename__ = "device_installation_users"
    __table_args__ = (
        Index("idx_device_installation_users_user_id", "user_id"),
        Index("idx_device_installation_users_installation_pk", "installation_pk"),
        Index(
            "uq_device_installation_users_active_installation",
            "installation_pk",
            unique=True,
            postgresql_where=text("unbound_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    installation_pk: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("device_installations.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    bound_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    unbound_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
