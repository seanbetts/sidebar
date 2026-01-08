"""Add last_opened_at to ingested files.

Revision ID: 017_add_ingested_files_last_opened_at
Revises: 016_add_ingested_files_source_fields
Create Date: 2026-01-04 13:00:00.000000
"""
import sqlalchemy as sa
from alembic import op

revision = "017_add_ingested_files_last_opened_at"
down_revision = "016_add_ingested_files_source_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ingested_files",
        sa.Column("last_opened_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "idx_ingested_files_last_opened_at",
        "ingested_files",
        ["last_opened_at"],
    )


def downgrade() -> None:
    op.drop_index("idx_ingested_files_last_opened_at", table_name="ingested_files")
    op.drop_column("ingested_files", "last_opened_at")
