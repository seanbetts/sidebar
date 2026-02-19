"""Add AI provider preference fields to user_settings.

Revision ID: 047_add_user_settings_ai_provider_preferences
Revises: 046_allow_unscoped_ingestion_worker_claims
Create Date: 2026-02-19 20:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "047_add_user_settings_ai_provider_preferences"
down_revision: str | None = "046_allow_unscoped_ingestion_worker_claims"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add user-level AI provider policy fields."""
    op.execute(
        "ALTER TABLE user_settings " "ADD COLUMN IF NOT EXISTS ai_primary_provider text"
    )
    op.execute(
        "ALTER TABLE user_settings "
        "ADD COLUMN IF NOT EXISTS ai_fallback_to_managed boolean DEFAULT true"
    )
    op.execute(
        "UPDATE user_settings "
        "SET ai_fallback_to_managed = true "
        "WHERE ai_fallback_to_managed IS NULL"
    )
    op.execute(
        "ALTER TABLE user_settings " "ALTER COLUMN ai_fallback_to_managed SET NOT NULL"
    )


def downgrade() -> None:
    """Remove AI provider policy fields from user_settings."""
    op.execute(
        "ALTER TABLE user_settings " "DROP COLUMN IF EXISTS ai_fallback_to_managed"
    )
    op.execute("ALTER TABLE user_settings " "DROP COLUMN IF EXISTS ai_primary_provider")
