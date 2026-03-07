"""Add normalized per-user skill state table.

Revision ID: 059_add_user_skill_states
Revises: 058_drop_legacy_note_rtf_columns
Create Date: 2026-03-07 15:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "059_add_user_skill_states"
down_revision: str | None = "058_drop_legacy_note_rtf_columns"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the normalized user_skill_states table."""
    op.create_table(
        "user_skill_states",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("skill_id", sa.Text(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("installed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "metadata",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_user_skill_states_user_id",
        "user_skill_states",
        ["user_id"],
    )
    op.create_index(
        "idx_user_skill_states_skill_id",
        "user_skill_states",
        ["skill_id"],
    )
    op.create_index(
        "uq_user_skill_states_active_user_skill",
        "user_skill_states",
        ["user_id", "skill_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    """Drop the normalized user_skill_states table."""
    op.drop_index(
        "uq_user_skill_states_active_user_skill",
        table_name="user_skill_states",
    )
    op.drop_index("idx_user_skill_states_skill_id", table_name="user_skill_states")
    op.drop_index("idx_user_skill_states_user_id", table_name="user_skill_states")
    op.drop_table("user_skill_states")
