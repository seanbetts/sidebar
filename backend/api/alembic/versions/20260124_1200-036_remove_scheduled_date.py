"""Remove scheduled_date from tasks.

Revision ID: 036_remove_scheduled_date
Revises: 035_add_task_performance_indexes
Create Date: 2026-01-24 12:00:00
"""

from alembic import op
import sqlalchemy as sa

revision = "036_remove_scheduled_date"
down_revision = "035_add_task_performance_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Drop scheduled_date and associated indexes."""
    op.execute(
        "UPDATE tasks SET deadline = scheduled_date "
        "WHERE deadline IS NULL AND scheduled_date IS NOT NULL"
    )

    op.drop_index("idx_tasks_today_lookup", table_name="tasks")
    op.create_index(
        "idx_tasks_today_lookup",
        "tasks",
        ["user_id", "status", "deadline"],
        postgresql_where=sa.text(
            "deleted_at IS NULL AND status NOT IN ('completed', 'trashed', 'someday')"
        ),
    )

    op.drop_index("idx_tasks_scheduled_date", table_name="tasks")
    op.drop_index("uq_tasks_repeat_template_date", table_name="tasks")
    op.create_index(
        "uq_tasks_repeat_template_deadline",
        "tasks",
        ["repeat_template_id", "deadline"],
        unique=True,
        postgresql_where=sa.text("repeat_template_id IS NOT NULL"),
    )

    op.drop_column("tasks", "scheduled_date")


def downgrade() -> None:
    """Restore scheduled_date and previous indexes."""
    op.add_column("tasks", sa.Column("scheduled_date", sa.Date(), nullable=True))

    op.drop_index("idx_tasks_today_lookup", table_name="tasks")
    op.create_index(
        "idx_tasks_today_lookup",
        "tasks",
        ["user_id", "status", "scheduled_date", "deadline"],
        postgresql_where=sa.text(
            "deleted_at IS NULL AND status NOT IN ('completed', 'trashed', 'someday')"
        ),
    )

    op.create_index("idx_tasks_scheduled_date", "tasks", ["scheduled_date"])
    op.drop_index("uq_tasks_repeat_template_deadline", table_name="tasks")
    op.create_index(
        "uq_tasks_repeat_template_date",
        "tasks",
        ["repeat_template_id", "scheduled_date"],
        unique=True,
        postgresql_where=sa.text("repeat_template_id IS NOT NULL"),
    )
