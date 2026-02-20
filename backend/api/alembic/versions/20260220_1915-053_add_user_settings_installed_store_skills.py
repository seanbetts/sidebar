"""Add installed_store_skills to user_settings.

Revision ID: 053_add_user_settings_installed_store_skills
Revises: 052_add_rls_to_user_ai_provider_keys
Create Date: 2026-02-20 19:15:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "053_add_user_settings_installed_store_skills"
down_revision: str | None = "052_add_rls_to_user_ai_provider_keys"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add installed_store_skills JSONB list field."""
    op.execute(
        "ALTER TABLE user_settings "
        "ADD COLUMN IF NOT EXISTS installed_store_skills jsonb"
    )


def downgrade() -> None:
    """Remove installed_store_skills field."""
    op.execute("ALTER TABLE user_settings DROP COLUMN IF EXISTS installed_store_skills")
