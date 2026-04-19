"""Add durable notification diagnostics audit rows.

Revision ID: 072_add_notification_diagnostics_audit
Revises: 071_fix_device_installation_rls_outer_reference
Create Date: 2026-04-19 12:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "072_add_notification_diagnostics_audit"
down_revision: str | None = "071_fix_device_installation_rls_outer_reference"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create the notification diagnostics audit table and indexes."""
    op.create_table(
        "notification_diagnostics_audit",
        sa.Column(
            "id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("notification_kind", sa.Text(), nullable=False),
        sa.Column("installation_id", sa.Text(), nullable=True),
        sa.Column("platform", sa.Text(), nullable=True),
        sa.Column("token_suffix", sa.Text(), nullable=True),
        sa.Column("apns_topic", sa.Text(), nullable=True),
        sa.Column("apns_env", sa.Text(), nullable=True),
        sa.Column("delivery_result", sa.Text(), nullable=False),
        sa.Column("skip_reason", sa.Text(), nullable=True),
        sa.Column("apns_status_code", sa.Integer(), nullable=True),
        sa.Column("apns_reason", sa.Text(), nullable=True),
    )
    op.execute(
        "CREATE INDEX idx_notification_diagnostics_audit_user_created_at "
        "ON notification_diagnostics_audit (user_id, created_at DESC)"
    )
    op.execute(
        "CREATE INDEX idx_notification_diagnostics_audit_installation_created_at "
        "ON notification_diagnostics_audit (installation_id, created_at DESC)"
    )
    op.execute(
        "CREATE INDEX idx_notification_diagnostics_audit_kind_created_at "
        "ON notification_diagnostics_audit (notification_kind, created_at DESC)"
    )


def downgrade() -> None:
    """Drop the notification diagnostics audit table."""
    op.drop_index(
        "idx_notification_diagnostics_audit_kind_created_at",
        table_name="notification_diagnostics_audit",
    )
    op.drop_index(
        "idx_notification_diagnostics_audit_installation_created_at",
        table_name="notification_diagnostics_audit",
    )
    op.drop_index(
        "idx_notification_diagnostics_audit_user_created_at",
        table_name="notification_diagnostics_audit",
    )
    op.drop_table("notification_diagnostics_audit")
