"""Add path column to ingested_files."""

import sqlalchemy as sa
from alembic import op

# Revision identifiers, used by Alembic.
revision = "018_add_ingested_files_path"
down_revision = "017_add_ingested_files_last_opened_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("ingested_files", sa.Column("path", sa.Text(), nullable=True))
    op.create_index("idx_ingested_files_path", "ingested_files", ["path"])
    op.execute("UPDATE ingested_files SET path = filename_original WHERE path IS NULL")


def downgrade() -> None:
    op.drop_index("idx_ingested_files_path", table_name="ingested_files")
    op.drop_column("ingested_files", "path")
