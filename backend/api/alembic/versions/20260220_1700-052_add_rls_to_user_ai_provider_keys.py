"""Enable RLS for user_ai_provider_keys.

Revision ID: 052_add_rls_to_user_ai_provider_keys
Revises: 051_drop_user_settings_ai_fallback_to_managed
Create Date: 2026-02-20 17:00:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "052_add_rls_to_user_ai_provider_keys"
down_revision: str | None = "051_drop_user_settings_ai_fallback_to_managed"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Enable RLS and add per-user isolation policy for provider keys."""
    op.execute("ALTER TABLE user_ai_provider_keys ENABLE ROW LEVEL SECURITY")
    op.execute(
        "DROP POLICY IF EXISTS user_ai_provider_keys_user_isolation "
        "ON user_ai_provider_keys"
    )
    op.execute(
        """
        CREATE POLICY user_ai_provider_keys_user_isolation
        ON user_ai_provider_keys
        USING (
            user_id = (SELECT current_setting('app.user_id', true))
            OR user_id = (SELECT auth.uid()::text)
        )
        WITH CHECK (
            user_id = (SELECT current_setting('app.user_id', true))
            OR user_id = (SELECT auth.uid()::text)
        )
        """
    )


def downgrade() -> None:
    """Remove provider-key policy and disable RLS."""
    op.execute(
        "DROP POLICY IF EXISTS user_ai_provider_keys_user_isolation "
        "ON user_ai_provider_keys"
    )
    op.execute("ALTER TABLE user_ai_provider_keys DISABLE ROW LEVEL SECURITY")
