"""Enable RLS for notification diagnostics tables.

Revision ID: 076_add_rls_to_notification_diagnostics_tables
Revises: 075_add_notification_worker_scope_to_user_settings
Create Date: 2026-05-06 09:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "076_add_rls_to_notification_diagnostics_tables"
down_revision: str | None = "075_add_notification_worker_scope_to_user_settings"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP_USER = "(SELECT current_setting('app.user_id', true))"
BACKEND_USER_PRESENT = "(SELECT current_setting('app.user_id', true)) IS NOT NULL"
NOTIFICATION_SCOPE = (
    "(SELECT current_setting('app.notification_worker_scope', true)) = 'all'"
)

USER_SCOPED_TABLES = (
    "notification_diagnostics_audit",
    "notification_scheduler_decisions",
)
WORKER_TABLES = (
    "notification_diagnostics_audit",
    "notification_scheduler_decisions",
    "notification_scheduler_heartbeat",
    "notification_scheduler_runs",
)
BACKEND_READ_TABLES = (
    "notification_scheduler_heartbeat",
    "notification_scheduler_runs",
)


def upgrade() -> None:
    """Enable RLS and add notification-worker/user-scoped policies."""
    for table in WORKER_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")

    _drop_policies()

    for table in WORKER_TABLES:
        op.execute(
            f"""
            CREATE POLICY {table}_notification_worker_operations
            ON {table}
            USING ({NOTIFICATION_SCOPE})
            WITH CHECK ({NOTIFICATION_SCOPE})
            """
        )

    for table in USER_SCOPED_TABLES:
        op.execute(
            f"""
            CREATE POLICY {table}_user_select
            ON {table}
            FOR SELECT
            USING (user_id = {APP_USER})
            """
        )
        op.execute(
            f"""
            CREATE POLICY {table}_user_insert
            ON {table}
            FOR INSERT
            WITH CHECK (user_id = {APP_USER})
            """
        )

    for table in BACKEND_READ_TABLES:
        op.execute(
            f"""
            CREATE POLICY {table}_backend_select
            ON {table}
            FOR SELECT
            USING ({BACKEND_USER_PRESENT})
            """
        )


def downgrade() -> None:
    """Remove notification diagnostics RLS policies and disable RLS."""
    _drop_policies()
    for table in WORKER_TABLES:
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")


def _drop_policies() -> None:
    """Drop notification diagnostics RLS policies created by this migration."""
    for table in WORKER_TABLES:
        op.execute(
            f"DROP POLICY IF EXISTS {table}_notification_worker_operations ON {table}"
        )

    for table in USER_SCOPED_TABLES:
        op.execute(f"DROP POLICY IF EXISTS {table}_user_select ON {table}")
        op.execute(f"DROP POLICY IF EXISTS {table}_user_insert ON {table}")

    for table in BACKEND_READ_TABLES:
        op.execute(f"DROP POLICY IF EXISTS {table}_backend_select ON {table}")
