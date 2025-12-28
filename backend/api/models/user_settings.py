"""User settings model for per-user prompts and preferences."""
from datetime import datetime, timezone

from sqlalchemy import Column, Date, DateTime, Text
from sqlalchemy.dialects.postgresql import JSONB

from api.db.base import Base


class UserSettings(Base):
    """Per-user settings for prompts and preferences."""

    __tablename__ = "user_settings"

    user_id = Column(Text, primary_key=True)
    system_prompt = Column(Text, nullable=True)
    first_message_prompt = Column(Text, nullable=True)
    communication_style = Column(Text, nullable=True)
    working_relationship = Column(Text, nullable=True)
    name = Column(Text, nullable=True)
    job_title = Column(Text, nullable=True)
    employer = Column(Text, nullable=True)
    date_of_birth = Column(Date, nullable=True)
    gender = Column(Text, nullable=True)
    pronouns = Column(Text, nullable=True)
    location = Column(Text, nullable=True)
    profile_image_path = Column(Text, nullable=True)
    enabled_skills = Column(JSONB, nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    def __repr__(self) -> str:
        """Return a readable representation for debugging."""
        return f"<UserSettings(user_id={self.user_id})>"
