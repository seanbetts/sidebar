"""User settings model for per-user prompts and preferences."""

from datetime import UTC, date, datetime

from sqlalchemy import Date, DateTime, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from api.db.base import Base


class UserSettings(Base):
    """Per-user settings for prompts and preferences."""

    __tablename__ = "user_settings"

    user_id: Mapped[str] = mapped_column(Text, primary_key=True)
    system_prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
    first_message_prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
    communication_style: Mapped[str | None] = mapped_column(Text, nullable=True)
    working_relationship: Mapped[str | None] = mapped_column(Text, nullable=True)
    name: Mapped[str | None] = mapped_column(Text, nullable=True)
    job_title: Mapped[str | None] = mapped_column(Text, nullable=True)
    employer: Mapped[str | None] = mapped_column(Text, nullable=True)
    date_of_birth: Mapped[date | None] = mapped_column(Date, nullable=True)
    gender: Mapped[str | None] = mapped_column(Text, nullable=True)
    pronouns: Mapped[str | None] = mapped_column(Text, nullable=True)
    location: Mapped[str | None] = mapped_column(Text, nullable=True)
    profile_image_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    enabled_skills: Mapped[list[str] | None] = mapped_column(JSONB, nullable=True)
    shortcuts_pat: Mapped[str | None] = mapped_column(Text, nullable=True)
    things_ai_snapshot: Mapped[str | None] = mapped_column(Text, nullable=True)
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

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<UserSettings(user_id={self.user_id})>"
