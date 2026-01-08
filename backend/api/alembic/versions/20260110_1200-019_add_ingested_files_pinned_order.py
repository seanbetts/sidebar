"""Add pinned_order to ingested files."""
import sqlalchemy as sa
from alembic import op

revision = "019_add_ingested_files_pinned_order"
down_revision = "018_add_ingested_files_path"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add pinned_order column."""
    op.add_column("ingested_files", sa.Column("pinned_order", sa.Integer(), nullable=True))


def downgrade() -> None:
    """Drop pinned_order column."""
    op.drop_column("ingested_files", "pinned_order")
