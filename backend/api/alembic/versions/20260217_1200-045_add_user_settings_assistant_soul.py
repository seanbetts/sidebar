"""Add assistant_soul column to user_settings.

Revision ID: 045_add_user_settings_assistant_soul
Revises: 044_add_user_settings_assistant_identity
Create Date: 2026-02-17 12:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "045_add_user_settings_assistant_soul"
down_revision: str | None = "044_add_user_settings_assistant_identity"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add assistant_soul JSONB settings payload."""
    op.execute(
        "ALTER TABLE user_settings ADD COLUMN IF NOT EXISTS assistant_soul jsonb"
    )


def downgrade() -> None:
    """Remove assistant_soul from user_settings."""
    op.execute("ALTER TABLE user_settings DROP COLUMN IF EXISTS assistant_soul")
