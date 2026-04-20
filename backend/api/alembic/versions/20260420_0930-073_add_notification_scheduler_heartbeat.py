"""Add notification scheduler heartbeat table.

Revision ID: 073_add_notification_scheduler_heartbeat
Revises: 072_add_notification_diagnostics_audit
Create Date: 2026-04-20 09:30:00.000000
"""

from alembic import op
import sqlalchemy as sa


revision: str = "073_add_notification_scheduler_heartbeat"
down_revision: str | None = "072_add_notification_diagnostics_audit"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "notification_scheduler_heartbeat",
        sa.Column("worker_name", sa.Text(), nullable=False),
        sa.Column("last_started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_status", sa.Text(), nullable=False),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("last_task_reminders_due", sa.Integer(), nullable=False),
        sa.Column("last_task_reminders_dispatched", sa.Integer(), nullable=False),
        sa.Column("last_morning_digests_due", sa.Integer(), nullable=False),
        sa.Column("last_morning_digests_dispatched", sa.Integer(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("worker_name"),
    )


def downgrade() -> None:
    op.drop_table("notification_scheduler_heartbeat")
