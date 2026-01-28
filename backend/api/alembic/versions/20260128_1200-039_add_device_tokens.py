"""Add device tokens table for push notifications.

Revision ID: 039_add_device_tokens
Revises: 038_rename_task_areas_to_groups
Create Date: 2026-01-28 12:00:00
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "039_add_device_tokens"
down_revision = "038_rename_task_areas_to_groups"
branch_labels = None
depends_on = None


USER_ISOLATION_POLICY = """
CREATE POLICY {policy}
ON {table}
USING (user_id = current_setting('app.user_id', true))
WITH CHECK (user_id = current_setting('app.user_id', true))
"""


def upgrade() -> None:
    """Create device token table with RLS policies."""
    op.create_table(
        "device_tokens",
        sa.Column(
            "id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False
        ),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("token", sa.Text(), nullable=False),
        sa.Column("platform", sa.Text(), nullable=False),
        sa.Column("environment", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("token", name="uq_device_tokens_token"),
    )
    op.create_index("idx_device_tokens_user_id", "device_tokens", ["user_id"])
    op.create_index("idx_device_tokens_token", "device_tokens", ["token"])
    op.create_index("idx_device_tokens_disabled_at", "device_tokens", ["disabled_at"])

    op.execute("ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY")
    op.execute("DROP POLICY IF EXISTS device_tokens_user_isolation ON device_tokens")
    op.execute(
        USER_ISOLATION_POLICY.format(
            policy="device_tokens_user_isolation", table="device_tokens"
        )
    )


def downgrade() -> None:
    """Drop device token table and policies."""
    op.execute("DROP POLICY IF EXISTS device_tokens_user_isolation ON device_tokens")
    op.execute("ALTER TABLE device_tokens DISABLE ROW LEVEL SECURITY")

    op.drop_index("idx_device_tokens_disabled_at", table_name="device_tokens")
    op.drop_index("idx_device_tokens_token", table_name="device_tokens")
    op.drop_index("idx_device_tokens_user_id", table_name="device_tokens")
    op.drop_table("device_tokens")
