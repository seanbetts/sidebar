"""Fix outer table reference in device installation RLS policy.

Revision ID: 071_fix_device_installation_rls_outer_reference
Revises: 070_add_rls_to_device_installations
Create Date: 2026-04-16 19:30:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "071_fix_device_installation_rls_outer_reference"
down_revision: str | None = "070_add_rls_to_device_installations"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP_USER = "(SELECT current_setting('app.user_id', true))"
AUTH_UID = "(SELECT auth.uid()::text)"


def upgrade() -> None:
    """Recreate the user isolation policy with an explicit outer-table reference."""
    op.execute(
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    )
    op.execute(
        f"""
        CREATE POLICY device_installations_user_isolation
        ON device_installations
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1
                FROM device_installation_users
                WHERE device_installation_users.installation_pk = device_installations.id
                  AND device_installation_users.unbound_at IS NULL
                  AND (
                    device_installation_users.user_id = {APP_USER}
                    OR device_installation_users.user_id = {AUTH_UID}
                  )
            )
        )
        """
    )


def downgrade() -> None:
    """Restore the original unqualified policy expression."""
    op.execute(
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    )
    op.execute(
        f"""
        CREATE POLICY device_installations_user_isolation
        ON device_installations
        FOR SELECT
        USING (
            EXISTS (
                SELECT 1
                FROM device_installation_users
                WHERE installation_pk = id
                  AND unbound_at IS NULL
                  AND (
                    user_id = {APP_USER}
                    OR user_id = {AUTH_UID}
                  )
            )
        )
        """
    )
