"""Allow notification worker reads on user_settings.

Revision ID: 075_add_notification_worker_scope_to_user_settings
Revises: 074_add_notification_scheduler_history_and_decisions
Create Date: 2026-04-20 20:45:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "075_add_notification_worker_scope_to_user_settings"
down_revision: str | None = "074_add_notification_scheduler_history_and_decisions"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP_USER = "(SELECT current_setting('app.user_id', true))"
NOTIFICATION_SCOPE = (
    "(SELECT current_setting('app.notification_worker_scope', true)) = 'all'"
)


def upgrade() -> None:
    """Add a read-only user_settings policy for the notification scheduler."""
    op.execute(
        "DROP POLICY IF EXISTS user_settings_notification_worker_select "
        "ON user_settings"
    )
    op.execute(
        f"""
        CREATE POLICY user_settings_notification_worker_select
        ON user_settings
        FOR SELECT
        USING (
            user_id = {APP_USER}
            OR {NOTIFICATION_SCOPE}
        )
        """
    )


def downgrade() -> None:
    """Remove the notification worker user_settings policy."""
    op.execute(
        "DROP POLICY IF EXISTS user_settings_notification_worker_select "
        "ON user_settings"
    )
