"""Add websites archived metadata index

Revision ID: 004
Revises: 003
Create Date: 2025-12-30 14:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "004"
down_revision: Union[str, None] = "003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


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
