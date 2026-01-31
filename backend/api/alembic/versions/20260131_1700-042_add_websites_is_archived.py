"""Add is_archived column to websites.

Revision ID: 042_add_websites_is_archived
Revises: 041_add_notes_is_archived
Create Date: 2026-01-31 17:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "042_add_websites_is_archived"
down_revision: str | None = "041_add_notes_is_archived"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


BATCH_SIZE = 10_000


def upgrade() -> None:
    """Add is_archived column for websites."""
    op.execute("SET statement_timeout TO '20min'")
    op.execute(
        "ALTER TABLE websites "
        "ADD COLUMN IF NOT EXISTS is_archived boolean "
        "DEFAULT false"
    )
    op.execute("ALTER TABLE websites ALTER COLUMN is_archived SET NOT NULL")

    with op.get_context().autocommit_block():
        conn = op.get_bind()
        while True:
            result = conn.execute(
                sa.text(
                    """
                    WITH batch AS (
                        SELECT id
                        FROM websites
                        WHERE is_archived IS DISTINCT FROM (
                            COALESCE(metadata->>'archived','false') = 'true'
                        )
                        LIMIT :limit
                    )
                    UPDATE websites AS w
                    SET is_archived = (
                        COALESCE(w.metadata->>'archived','false') = 'true'
                    )
                    FROM batch
                    WHERE w.id = batch.id
                    RETURNING w.id
                    """
                ),
                {"limit": BATCH_SIZE},
            )
            if result.rowcount == 0:
                break

    with op.get_context().autocommit_block():
        op.execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
            "idx_websites_user_archived_updated "
            "ON websites (user_id, is_archived, updated_at DESC) "
            "WHERE deleted_at IS NULL"
        )
    op.execute("SET statement_timeout TO DEFAULT")


def downgrade() -> None:
    """Remove is_archived column for websites."""
    with op.get_context().autocommit_block():
        op.execute("DROP INDEX IF EXISTS idx_websites_user_archived_updated")
    op.execute("ALTER TABLE websites DROP COLUMN IF EXISTS is_archived")
