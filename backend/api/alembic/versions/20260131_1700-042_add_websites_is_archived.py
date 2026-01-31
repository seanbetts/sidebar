"""Add generated is_archived column to websites.

Revision ID: 042_add_websites_is_archived
Revises: 041_add_notes_is_archived
Create Date: 2026-01-31 17:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "042_add_websites_is_archived"
down_revision: str | None = "041_add_notes_is_archived"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add generated is_archived column for websites."""
    op.execute("SET statement_timeout TO '10min'")
    op.execute(
        "ALTER TABLE websites "
        "ADD COLUMN IF NOT EXISTS is_archived boolean "
        "GENERATED ALWAYS AS ("
        "(COALESCE(metadata->>'archived','false') = 'true')"
        ") STORED"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_websites_user_archived_updated "
        "ON websites (user_id, is_archived, updated_at DESC) "
        "WHERE deleted_at IS NULL"
    )
    op.execute("SET statement_timeout TO DEFAULT")


def downgrade() -> None:
    """Remove generated is_archived column for websites."""
    op.execute("SET statement_timeout TO '10min'")
    op.execute("DROP INDEX IF EXISTS idx_websites_user_archived_updated")
    op.execute("ALTER TABLE websites DROP COLUMN IF EXISTS is_archived")
    op.execute("SET statement_timeout TO DEFAULT")
