"""Things bridge registration model."""

import uuid
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime, Index, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class ThingsBridge(Base):
    """Track registered Things bridge hosts."""

    __tablename__ = "things_bridges"
    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_things_bridges_user_device"),
        Index("idx_things_bridges_user_id", "user_id"),
        Index("idx_things_bridges_last_seen", "last_seen_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    device_id: Mapped[str] = mapped_column(Text, nullable=False)
    device_name: Mapped[str] = mapped_column(Text, nullable=False)
    base_url: Mapped[str] = mapped_column(Text, nullable=False)
    bridge_token: Mapped[str] = mapped_column(Text, nullable=False)
    capabilities: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC), nullable=False
    )
