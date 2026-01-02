"""Things bridge install token model."""
from datetime import datetime, timezone
import uuid

from sqlalchemy import Column, DateTime, Text, Index
from sqlalchemy.dialects.postgresql import UUID

from api.db.base import Base


class ThingsBridgeInstallToken(Base):
    """One-time install tokens for Things bridge setup."""

    __tablename__ = "things_bridge_install_tokens"
    __table_args__ = (
        Index("idx_things_bridge_install_user_id", "user_id"),
        Index("idx_things_bridge_install_token_hash", "token_hash"),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Text, nullable=False)
    token_hash = Column(Text, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False)
