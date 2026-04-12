"""Add retention tracking columns and cleanup indexes.

Revision ID: 068_add_retention_tracking_and_cleanup_indexes
Revises: 067_create_device_installations_and_bindings
Create Date: 2026-04-11 18:00:00
"""

from collections.abc import Sequence
import time

import sqlalchemy as sa
from alembic import op
from sqlalchemy.exc import OperationalError

revision: str = "068_add_retention_tracking_and_cleanup_indexes"
down_revision: str | None = "067_create_device_installations_and_bindings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

LOCK_TIMEOUT = "2s"
LOCK_RETRY_SLEEP_SECONDS = 2
MAX_LOCK_RETRIES = 300


def _execute_with_lock_retry(conn, statement: str) -> None:
    """Execute DDL with bounded retries on lock timeout."""
    for attempt in range(MAX_LOCK_RETRIES):
        try:
            conn.execute(sa.text(statement))
            return
        except OperationalError as exc:
            if getattr(exc.orig, "pgcode", None) != "55P03":
                raise
            if attempt == MAX_LOCK_RETRIES - 1:
                raise
            time.sleep(LOCK_RETRY_SLEEP_SECONDS)


def upgrade() -> None:
    """Add retention-tracking columns and cleanup-supporting indexes."""
    with op.get_context().autocommit_block():
        conn = op.get_bind()
        conn.execute(sa.text("SET statement_timeout TO '20min'"))
        conn.execute(sa.text(f"SET lock_timeout TO '{LOCK_TIMEOUT}'"))
        _execute_with_lock_retry(
            conn,
            "ALTER TABLE notes "
            "ADD COLUMN IF NOT EXISTS payload_purged_at TIMESTAMP WITH TIME ZONE",
        )
        _execute_with_lock_retry(
            conn,
            "ALTER TABLE websites "
            "ADD COLUMN IF NOT EXISTS payload_purged_at TIMESTAMP WITH TIME ZONE",
        )
        conn.execute(sa.text("SET lock_timeout TO DEFAULT"))
        conn.execute(sa.text("SET statement_timeout TO DEFAULT"))

    with op.get_context().autocommit_block():
        conn = op.get_bind()
        conn.execute(sa.text("SET statement_timeout TO '20min'"))
        conn.execute(
            sa.text(
                "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
                "ix_notes_payload_purged_at ON notes (payload_purged_at)"
            )
        )
        conn.execute(
            sa.text(
                "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
                "ix_websites_payload_purged_at ON websites (payload_purged_at)"
            )
        )
        conn.execute(
            sa.text(
                "CREATE INDEX CONCURRENTLY IF NOT EXISTS "
                "idx_website_jobs_updated_at ON website_processing_jobs (updated_at)"
            )
        )
        conn.execute(sa.text("SET statement_timeout TO DEFAULT"))


def downgrade() -> None:
    """Remove retention-tracking columns and cleanup-supporting indexes."""
    with op.get_context().autocommit_block():
        conn = op.get_bind()
        conn.execute(
            sa.text("DROP INDEX CONCURRENTLY IF EXISTS idx_website_jobs_updated_at")
        )
        conn.execute(
            sa.text("DROP INDEX CONCURRENTLY IF EXISTS ix_websites_payload_purged_at")
        )
        conn.execute(
            sa.text("DROP INDEX CONCURRENTLY IF EXISTS ix_notes_payload_purged_at")
        )

    with op.get_context().autocommit_block():
        conn = op.get_bind()
        conn.execute(sa.text(f"SET lock_timeout TO '{LOCK_TIMEOUT}'"))
        _execute_with_lock_retry(
            conn,
            "ALTER TABLE websites DROP COLUMN IF EXISTS payload_purged_at",
        )
        _execute_with_lock_retry(
            conn,
            "ALTER TABLE notes DROP COLUMN IF EXISTS payload_purged_at",
        )
        conn.execute(sa.text("SET lock_timeout TO DEFAULT"))
