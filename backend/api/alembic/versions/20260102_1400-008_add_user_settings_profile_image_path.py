"""Add user settings profile image path

Revision ID: 008
Revises: 007
Create Date: 2026-01-02 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add profile image path field."""
    op.add_column("user_settings", sa.Column("profile_image_path", sa.Text(), nullable=True))


def downgrade() -> None:
    """Remove profile image path field."""
    op.drop_column("user_settings", "profile_image_path")
