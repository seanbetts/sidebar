"""Add reading_time column to websites.

Revision ID: 043_add_websites_reading_time
Revises: 042_add_websites_is_archived
Create Date: 2026-02-06 22:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "043_add_websites_reading_time"
down_revision: str | None = "042_add_websites_is_archived"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add reading_time column and seed from metadata when available."""
    op.execute("ALTER TABLE websites " "ADD COLUMN IF NOT EXISTS reading_time text")
    op.execute(
        "UPDATE websites "
        "SET reading_time = metadata->>'reading_time' "
        "WHERE reading_time IS NULL "
        "AND metadata ? 'reading_time'"
    )


def downgrade() -> None:
    """Remove reading_time column from websites."""
    op.execute("ALTER TABLE websites DROP COLUMN IF EXISTS reading_time")
