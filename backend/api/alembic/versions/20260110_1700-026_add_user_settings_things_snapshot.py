"""Add Things AI snapshot to user settings.

Revision ID: 026_add_user_settings_things_snapshot
Revises: 025_add_things_bridge_install_tokens
Create Date: 2026-01-10 17:00:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision = "026_add_user_settings_things_snapshot"
down_revision = "025_add_things_bridge_install_tokens"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("user_settings", sa.Column("things_ai_snapshot", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("user_settings", "things_ai_snapshot")
