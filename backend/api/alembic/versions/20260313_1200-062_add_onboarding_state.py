"""Add onboarding JSONB column to user_settings.

Revision ID: 062_add_onboarding_state
Revises: 061_remove_task_inbox_status
Create Date: 2026-03-13 12:00:00.000000
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "062_add_onboarding_state"
down_revision: str | None = "061_remove_task_inbox_status"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Add nullable onboarding JSONB column to user_settings."""
    op.add_column(
        "user_settings",
        sa.Column(
            "onboarding",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )


def downgrade() -> None:
    """Drop onboarding column from user_settings."""
    op.drop_column("user_settings", "onboarding")
