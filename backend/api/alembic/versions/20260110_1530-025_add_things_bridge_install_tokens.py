"""Add legacy bridge install tokens table.

Revision ID: 025_add_things_bridge_install_tokens
Revises: 024_add_things_bridges
Create Date: 2026-01-10 15:30:00
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "025_add_things_bridge_install_tokens"
down_revision = "024_add_things_bridges"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "things_bridge_install_tokens",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("token_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "idx_things_bridge_install_user_id",
        "things_bridge_install_tokens",
        ["user_id"],
    )
    op.create_index(
        "idx_things_bridge_install_token_hash",
        "things_bridge_install_tokens",
        ["token_hash"],
    )


def downgrade() -> None:
    op.drop_index("idx_things_bridge_install_token_hash", table_name="things_bridge_install_tokens")
    op.drop_index("idx_things_bridge_install_user_id", table_name="things_bridge_install_tokens")
    op.drop_table("things_bridge_install_tokens")
