"""Add assistant_identity column to user_settings.

Revision ID: 044_add_user_settings_assistant_identity
Revises: 043_add_websites_reading_time
Create Date: 2026-02-16 22:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "044_add_user_settings_assistant_identity"
down_revision: str | None = "043_add_websites_reading_time"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add assistant_identity JSONB settings payload."""
    op.execute(
        "ALTER TABLE user_settings " "ADD COLUMN IF NOT EXISTS assistant_identity jsonb"
    )


def downgrade() -> None:
    """Remove assistant_identity from user_settings."""
    op.execute("ALTER TABLE user_settings DROP COLUMN IF EXISTS assistant_identity")
