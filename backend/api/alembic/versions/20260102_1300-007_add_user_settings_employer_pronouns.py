"""Add user settings employer and pronouns

Revision ID: 007
Revises: 006
Create Date: 2026-01-02 13:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "007"
down_revision: str | None = "006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add employer and pronouns fields."""
    op.add_column("user_settings", sa.Column("employer", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("pronouns", sa.Text(), nullable=True))


def downgrade() -> None:
    """Remove employer and pronouns fields."""
    op.drop_column("user_settings", "pronouns")
    op.drop_column("user_settings", "employer")
