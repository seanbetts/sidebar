"""Add user memories table

Revision ID: 010
Revises: 009
Create Date: 2026-01-03 12:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "010"
down_revision: str | None = "009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create user memories table."""
    op.create_table(
        "user_memories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "path", name="uq_user_memories_user_id_path"),
    )
    op.create_index(
        "idx_user_memories_user_id_path",
        "user_memories",
        ["user_id", "path"],
    )


def downgrade() -> None:
    """Drop user memories table."""
    op.drop_index("idx_user_memories_user_id_path", table_name="user_memories")
    op.drop_table("user_memories")
