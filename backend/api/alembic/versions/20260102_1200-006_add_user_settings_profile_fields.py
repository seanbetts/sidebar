"""Add user settings profile fields

Revision ID: 006
Revises: 005
Create Date: 2026-01-02 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add profile and prompt customization fields."""
    op.add_column("user_settings", sa.Column("communication_style", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("working_relationship", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("name", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("job_title", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("date_of_birth", sa.Date(), nullable=True))
    op.add_column("user_settings", sa.Column("gender", sa.Text(), nullable=True))
    op.add_column("user_settings", sa.Column("location", sa.Text(), nullable=True))


def downgrade() -> None:
    """Remove profile and prompt customization fields."""
    op.drop_column("user_settings", "location")
    op.drop_column("user_settings", "gender")
    op.drop_column("user_settings", "date_of_birth")
    op.drop_column("user_settings", "job_title")
    op.drop_column("user_settings", "name")
    op.drop_column("user_settings", "working_relationship")
    op.drop_column("user_settings", "communication_style")
