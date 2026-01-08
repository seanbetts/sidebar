"""Add websites archived metadata index

Revision ID: 004
Revises: 003
Create Date: 2025-12-30 14:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "004"
down_revision: str | None = "003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add archived index for websites metadata."""
    op.execute(
        "UPDATE websites "
        "SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{archived}', 'true'::jsonb, true)"
    )
    op.create_index(
        "idx_websites_metadata_archived",
        "websites",
        [sa.text("(metadata->>'archived')")],
    )


def downgrade() -> None:
    """Drop archived index for websites metadata."""
    op.drop_index("idx_websites_metadata_archived", table_name="websites")
