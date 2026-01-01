"""Add pinned flag to ingested files."""

from alembic import op
import sqlalchemy as sa


revision = "015_add_ingested_files_pinned"
down_revision = "014_add_file_ingestion_tables"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add pinned column to ingested_files."""
    op.add_column(
        "ingested_files",
        sa.Column("pinned", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )
    op.alter_column("ingested_files", "pinned", server_default=None)


def downgrade() -> None:
    """Drop pinned column from ingested_files."""
    op.drop_column("ingested_files", "pinned")
