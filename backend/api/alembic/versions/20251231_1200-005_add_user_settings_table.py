"""Add user settings table

Revision ID: 005
Revises: 004
Create Date: 2025-12-31 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "005"
down_revision: Union[str, None] = "004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create user settings table."""
    op.create_table(
        "user_settings",
        sa.Column("user_id", sa.Text(), primary_key=True),
        sa.Column("system_prompt", sa.Text(), nullable=True),
        sa.Column("first_message_prompt", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    """Drop user settings table."""
    op.drop_table("user_settings")
