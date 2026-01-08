"""Add shortcuts PAT to user settings.

Revision ID: 020_add_user_settings_shortcuts_pat
Revises: 019_add_ingested_files_pinned_order
Create Date: 2026-01-10 13:00:00
"""

import sqlalchemy as sa
from alembic import op

revision = "020_add_user_settings_shortcuts_pat"
down_revision = "019_add_ingested_files_pinned_order"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("user_settings", sa.Column("shortcuts_pat", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("user_settings", "shortcuts_pat")
