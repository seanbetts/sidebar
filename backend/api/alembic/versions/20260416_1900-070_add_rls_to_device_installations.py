"""Enable RLS for device installation tables.

Revision ID: 070_add_rls_to_device_installations
Revises: 069_add_retention_worker_scope_to_cleanup_policies
Create Date: 2026-04-16 19:00:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "070_add_rls_to_device_installations"
down_revision: str | None = "069_add_retention_worker_scope_to_cleanup_policies"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP_USER = "(SELECT current_setting('app.user_id', true))"
AUTH_UID = "(SELECT auth.uid()::text)"
BACKEND_SCOPE = "current_setting('app.user_id', true) IS NOT NULL"


def upgrade() -> None:
    """Enable RLS and add user-scoped and backend-scoped policies."""
    op.execute("ALTER TABLE device_installations ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE device_installation_users ENABLE ROW LEVEL SECURITY")

    op.execute(
        "DROP POLICY IF EXISTS device_installations_backend_operations "
        "ON device_installations"
    )
    op.execute(
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    )
    op.execute(
        "DROP POLICY IF EXISTS device_installation_users_backend_operations "
        "ON device_installation_users"
    )
    op.execute(
        "DROP POLICY IF EXISTS device_installation_users_user_isolation "
        "ON device_installation_users"
    )

    op.execute(
        f"""
        CREATE POLICY device_installations_backend_operations
        ON device_installations
        USING ({BACKEND_SCOPE})
        WITH CHECK ({BACKEND_SCOPE})
        """
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
    op.execute(
        f"""
        CREATE POLICY device_installation_users_backend_operations
        ON device_installation_users
        USING ({BACKEND_SCOPE})
        WITH CHECK ({BACKEND_SCOPE})
        """
    )
    op.execute(
        f"""
        CREATE POLICY device_installation_users_user_isolation
        ON device_installation_users
        FOR SELECT
        USING (
            user_id = {APP_USER}
            OR user_id = {AUTH_UID}
        )
        """
    )


def downgrade() -> None:
    """Remove device installation policies and disable RLS."""
    op.execute(
        "DROP POLICY IF EXISTS device_installations_backend_operations "
        "ON device_installations"
    )
    op.execute(
        "DROP POLICY IF EXISTS device_installations_user_isolation "
        "ON device_installations"
    )
    op.execute(
        "DROP POLICY IF EXISTS device_installation_users_backend_operations "
        "ON device_installation_users"
    )
    op.execute(
        "DROP POLICY IF EXISTS device_installation_users_user_isolation "
        "ON device_installation_users"
    )

    op.execute("ALTER TABLE device_installations DISABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE device_installation_users DISABLE ROW LEVEL SECURITY")
