"""Things bridge registration model."""
from datetime import datetime, timezone
import uuid

from sqlalchemy import Column, DateTime, Text, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID

from api.db.base import Base


class ThingsBridge(Base):
    """Track registered Things bridge hosts."""

    __tablename__ = "things_bridges"
    __table_args__ = (
        UniqueConstraint("user_id", "device_id", name="uq_things_bridges_user_device"),
        Index("idx_things_bridges_user_id", "user_id"),
        Index("idx_things_bridges_last_seen", "last_seen_at"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    device_id = Column(Text, nullable=False)
    device_name = Column(Text, nullable=False)
    base_url = Column(Text, nullable=False)
    bridge_token = Column(Text, nullable=False)
    capabilities = Column(JSONB, nullable=True)
    last_seen_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
