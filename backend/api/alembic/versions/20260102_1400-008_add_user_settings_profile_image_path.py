"""Add user settings profile image path

Revision ID: 008
Revises: 007
Create Date: 2026-01-02 14:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "008"
down_revision: str | None = "007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add profile image path field."""
    op.add_column("user_settings", sa.Column("profile_image_path", sa.Text(), nullable=True))


def downgrade() -> None:
    """Remove profile image path field."""
    op.drop_column("user_settings", "profile_image_path")
