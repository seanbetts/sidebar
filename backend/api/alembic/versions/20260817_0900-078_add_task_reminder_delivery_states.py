"""Add durable task-reminder delivery progress.

Revision ID: 078_add_task_reminder_delivery_states
Revises: 077_grant_realtime_table_select
Create Date: 2026-08-17 09:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "078_add_task_reminder_delivery_states"
down_revision: str | None = "077_grant_realtime_table_select"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

TABLE = "task_reminder_delivery_states"
APP_USER = "(SELECT current_setting('app.user_id', true))"
NOTIFICATION_SCOPE = (
    "(SELECT current_setting('app.notification_worker_scope', true)) = 'all'"
)


def upgrade() -> None:
    """Create bounded delivery progress with backend-only scoped RLS."""
    op.create_table(
        TABLE,
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("schedule_timezone", sa.Text(), nullable=False),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column(
            "accepted_delivery_keys",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
        ),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["user_settings.user_id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "schedule_timezone",
            name="uq_task_reminder_delivery_states_user_timezone",
        ),
    )
    op.execute(f"ALTER TABLE {TABLE} ENABLE ROW LEVEL SECURITY")
    op.execute(
        f"""
        CREATE POLICY {TABLE}_user_operations
        ON {TABLE}
        USING (user_id = {APP_USER})
        WITH CHECK (user_id = {APP_USER})
        """
    )
    op.execute(
        f"""
        CREATE POLICY {TABLE}_worker_select
        ON {TABLE}
        FOR SELECT
        USING ({NOTIFICATION_SCOPE})
        """
    )


def downgrade() -> None:
    """Remove durable task-reminder delivery progress."""
    op.execute(f"DROP POLICY IF EXISTS {TABLE}_worker_select ON {TABLE}")
    op.execute(f"DROP POLICY IF EXISTS {TABLE}_user_operations ON {TABLE}")
    op.drop_table(TABLE)
