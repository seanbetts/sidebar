"""Add retention tracking columns and cleanup indexes.

Revision ID: 068_add_retention_tracking_and_cleanup_indexes
Revises: 067_create_device_installations_and_bindings
Create Date: 2026-04-11 18:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "068_add_retention_tracking_and_cleanup_indexes"
down_revision: str | None = "067_create_device_installations_and_bindings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add retention-tracking columns and cleanup-supporting indexes."""
    op.execute("SET statement_timeout TO '20min'")
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS payload_purged_at TIMESTAMP WITH TIME ZONE"
    )
    op.execute(
        "ALTER TABLE websites "
        "ADD COLUMN IF NOT EXISTS payload_purged_at TIMESTAMP WITH TIME ZONE"
    )

    with op.get_context().autocommit_block():
        op.execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
            "ix_notes_payload_purged_at ON notes (payload_purged_at)"
        )
        op.execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
            "ix_websites_payload_purged_at ON websites (payload_purged_at)"
        )
        op.execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
            "idx_website_jobs_updated_at ON website_processing_jobs (updated_at)"
        )
    op.execute("SET statement_timeout TO DEFAULT")


def downgrade() -> None:
    """Remove retention-tracking columns and cleanup-supporting indexes."""
    with op.get_context().autocommit_block():
        op.execute("DROP INDEX CONCURRENTLY IF EXISTS idx_website_jobs_updated_at")
        op.execute("DROP INDEX CONCURRENTLY IF EXISTS ix_websites_payload_purged_at")
        op.execute("DROP INDEX CONCURRENTLY IF EXISTS ix_notes_payload_purged_at")

    op.execute(
        "ALTER TABLE websites DROP COLUMN IF EXISTS payload_purged_at"
    )
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS payload_purged_at")
