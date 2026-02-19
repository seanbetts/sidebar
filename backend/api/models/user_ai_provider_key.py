"""Per-user encrypted BYOK credentials by provider."""

import uuid
from datetime import UTC, datetime

from sqlalchemy import DateTime, Index, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class UserAIProviderKey(Base):
    """Stores encrypted provider API keys for a user."""

    __tablename__ = "user_ai_provider_keys"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[str] = mapped_column(Text, nullable=False)
    provider: Mapped[str] = mapped_column(Text, nullable=False)
    encrypted_api_key: Mapped[str] = mapped_column(Text, nullable=False)
    key_last4: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        nullable=False,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    __table_args__ = (
        Index("idx_user_ai_provider_keys_user_id", "user_id"),
        Index("idx_user_ai_provider_keys_provider", "provider"),
        Index(
            "uq_user_ai_provider_keys_active_user_provider",
            "user_id",
            "provider",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return (
            f"<UserAIProviderKey(user_id={self.user_id}, provider={self.provider}, "
            f"deleted_at={self.deleted_at})>"
        )
