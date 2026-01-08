"""Add source fields to ingested files.

Revision ID: 016_add_ingested_files_source_fields
Revises: 015_add_ingested_files_pinned
Create Date: 2026-01-04 12:00:00.000000
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "016_add_ingested_files_source_fields"
down_revision = "015_add_ingested_files_pinned"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "ingested_files",
        sa.Column("source_url", sa.Text(), nullable=True),
    )
    op.add_column(
        "ingested_files",
        sa.Column("source_metadata", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("ingested_files", "source_metadata")
    op.drop_column("ingested_files", "source_url")
