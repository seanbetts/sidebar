"""Add updated_at to ingested_files.

Revision ID: 040_add_ingested_files_updated_at
Revises: 039_add_device_tokens
Create Date: 2026-01-30 12:00:00
"""

import sqlalchemy as sa
from alembic import op

revision = "040_add_ingested_files_updated_at"
down_revision = "039_add_device_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add updated_at column for ingested files."""
    op.add_column(
        "ingested_files",
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.execute(
        "UPDATE ingested_files SET updated_at = created_at WHERE updated_at IS NULL"
    )
    op.alter_column("ingested_files", "updated_at", nullable=False)
    op.create_index("idx_ingested_files_updated_at", "ingested_files", ["updated_at"])


def downgrade() -> None:
    """Remove updated_at column for ingested files."""
    op.drop_index("idx_ingested_files_updated_at", table_name="ingested_files")
    op.drop_column("ingested_files", "updated_at")
