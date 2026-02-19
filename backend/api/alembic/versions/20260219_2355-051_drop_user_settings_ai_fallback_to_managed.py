"""Drop deprecated ai_fallback_to_managed from user_settings.

Revision ID: 051_drop_user_settings_ai_fallback_to_managed
Revises: 050_default_ai_fallback_strict
Create Date: 2026-02-19 23:55:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "051_drop_user_settings_ai_fallback_to_managed"
down_revision: str | None = "050_default_ai_fallback_strict"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Drop deprecated strict-BYOK fallback column."""
    op.execute(
        "ALTER TABLE user_settings " "DROP COLUMN IF EXISTS ai_fallback_to_managed"
    )


def downgrade() -> None:
    """Recreate fallback column for backwards compatibility."""
    op.execute(
        "ALTER TABLE user_settings "
        "ADD COLUMN IF NOT EXISTS ai_fallback_to_managed boolean DEFAULT false"
    )
    op.execute(
        "UPDATE user_settings "
        "SET ai_fallback_to_managed = false "
        "WHERE ai_fallback_to_managed IS NULL"
    )
    op.execute(
        "ALTER TABLE user_settings " "ALTER COLUMN ai_fallback_to_managed SET NOT NULL"
    )
