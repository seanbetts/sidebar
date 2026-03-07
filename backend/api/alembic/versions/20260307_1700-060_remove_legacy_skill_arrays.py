"""Remove legacy skill arrays from user_settings.

Revision ID: 060_remove_legacy_skill_arrays
Revises: 059_add_user_skill_states
Create Date: 2026-03-07 17:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "060_remove_legacy_skill_arrays"
down_revision: str | None = "059_add_user_skill_states"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Drop deprecated skill-array columns now superseded by user_skill_states."""
    op.execute("ALTER TABLE user_settings DROP COLUMN IF EXISTS installed_store_skills")
    op.execute("ALTER TABLE user_settings DROP COLUMN IF EXISTS enabled_skills")


def downgrade() -> None:
    """Restore deprecated skill-array columns for rollback."""
    op.add_column(
        "user_settings",
        sa.Column(
            "enabled_skills", postgresql.JSONB(astext_type=sa.Text()), nullable=True
        ),
    )
    op.add_column(
        "user_settings",
        sa.Column(
            "installed_store_skills",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )
