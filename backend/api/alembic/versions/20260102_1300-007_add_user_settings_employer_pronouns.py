"""Add user settings employer and pronouns

Revision ID: 007
Revises: 006
Create Date: 2026-01-02 13:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add employer and pronouns fields."""
    op.add_column("user_settings", sa.Column("employer", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("pronouns", sa.Text(), nullable=True))


def downgrade() -> None:
    """Remove employer and pronouns fields."""
    op.drop_column("user_settings", "pronouns")
    op.drop_column("user_settings", "employer")
