"""add notification scheduler history and decision audits

Revision ID: 074_add_notification_scheduler_history_and_decisions
Revises: 073_add_notification_scheduler_heartbeat
Create Date: 2026-04-20 12:30:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "074_add_notification_scheduler_history_and_decisions"
down_revision: str | None = "073_add_notification_scheduler_heartbeat"
branch_labels: tuple[str, ...] | None = None
depends_on: tuple[str, ...] | None = None


def upgrade() -> None:
    op.create_table(
        "notification_scheduler_runs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("worker_name", sa.Text(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("task_reminders_due", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "task_reminders_dispatched",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("morning_digests_due", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "morning_digests_dispatched",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_notification_scheduler_runs_started_at",
        "notification_scheduler_runs",
        ["started_at"],
        unique=False,
    )
    op.create_index(
        "idx_notification_scheduler_runs_created_at",
        "notification_scheduler_runs",
        ["created_at"],
        unique=False,
    )
    op.create_index(
        "idx_notification_scheduler_runs_status",
        "notification_scheduler_runs",
        ["status"],
        unique=False,
    )

    op.create_table(
        "notification_scheduler_decisions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("worker_name", sa.Text(), nullable=False),
        sa.Column("run_started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("notification_kind", sa.Text(), nullable=False),
        sa.Column("decision_stage", sa.Text(), nullable=False),
        sa.Column("decision_reason", sa.Text(), nullable=False),
        sa.Column("scheduled_time", sa.Text(), nullable=True),
        sa.Column("schedule_timezone", sa.Text(), nullable=True),
        sa.Column("local_now", sa.DateTime(timezone=True), nullable=True),
        sa.Column("detail", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_notification_scheduler_decisions_user_created",
        "notification_scheduler_decisions",
        ["user_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_notification_scheduler_decisions_run_started",
        "notification_scheduler_decisions",
        ["run_started_at", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_notification_scheduler_decisions_reason_created",
        "notification_scheduler_decisions",
        ["decision_reason", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "idx_notification_scheduler_decisions_reason_created",
        table_name="notification_scheduler_decisions",
    )
    op.drop_index(
        "idx_notification_scheduler_decisions_run_started",
        table_name="notification_scheduler_decisions",
    )
    op.drop_index(
        "idx_notification_scheduler_decisions_user_created",
        table_name="notification_scheduler_decisions",
    )
    op.drop_table("notification_scheduler_decisions")

    op.drop_index(
        "idx_notification_scheduler_runs_status",
        table_name="notification_scheduler_runs",
    )
    op.drop_index(
        "idx_notification_scheduler_runs_created_at",
        table_name="notification_scheduler_runs",
    )
    op.drop_index(
        "idx_notification_scheduler_runs_started_at",
        table_name="notification_scheduler_runs",
    )
    op.drop_table("notification_scheduler_runs")
