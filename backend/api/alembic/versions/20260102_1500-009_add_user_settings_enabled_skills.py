"""Add user settings enabled skills field

Revision ID: 009
Revises: 008
Create Date: 2026-01-02 15:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "009"
down_revision: str | None = "008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add enabled skills list field."""
    op.add_column(
        "user_settings",
        sa.Column("enabled_skills", postgresql.JSONB(), nullable=True),
    )


def downgrade() -> None:
    """Remove enabled skills list field."""
    op.drop_column("user_settings", "enabled_skills")
