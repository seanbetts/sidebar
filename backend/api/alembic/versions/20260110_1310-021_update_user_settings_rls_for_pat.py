"""Allow PAT lookup for user settings RLS.

Revision ID: 021_update_user_settings_rls_for_pat
Revises: 020_add_user_settings_shortcuts_pat
Create Date: 2026-01-10 13:10:00
"""

from alembic import op


revision = "021_update_user_settings_rls_for_pat"
down_revision = "020_add_user_settings_shortcuts_pat"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY")
    op.execute("DROP POLICY IF EXISTS user_settings_user_isolation ON user_settings")
    op.execute(
        """
        CREATE POLICY user_settings_user_isolation
        ON user_settings
        USING (
            user_id = current_setting('app.user_id', true)
            OR shortcuts_pat = current_setting('app.pat_token', true)
        )
        WITH CHECK (
            user_id = current_setting('app.user_id', true)
        )
        """
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS user_settings_user_isolation ON user_settings")
    op.execute(
        """
        CREATE POLICY user_settings_user_isolation
        ON user_settings
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )
