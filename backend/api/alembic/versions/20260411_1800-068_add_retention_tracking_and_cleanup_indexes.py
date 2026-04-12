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
    op.add_column(
        "notes",
        sa.Column("payload_purged_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_notes_payload_purged_at",
        "notes",
        ["payload_purged_at"],
        unique=False,
    )

    op.add_column(
        "websites",
        sa.Column("payload_purged_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_websites_payload_purged_at",
        "websites",
        ["payload_purged_at"],
        unique=False,
    )

    op.create_index(
        "idx_website_jobs_updated_at",
        "website_processing_jobs",
        ["updated_at"],
        unique=False,
    )


def downgrade() -> None:
    """Remove retention-tracking columns and cleanup-supporting indexes."""
    op.drop_index("idx_website_jobs_updated_at", table_name="website_processing_jobs")

    op.drop_index("ix_websites_payload_purged_at", table_name="websites")
    op.drop_column("websites", "payload_purged_at")

    op.drop_index("ix_notes_payload_purged_at", table_name="notes")
    op.drop_column("notes", "payload_purged_at")
