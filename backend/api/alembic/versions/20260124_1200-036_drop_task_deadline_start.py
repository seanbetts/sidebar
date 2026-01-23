"""Drop tasks.deadline_start.

Revision ID: 036_drop_task_deadline_start
Revises: 035_add_task_performance_indexes
Create Date: 2026-01-24 12:00:00
"""

from alembic import op
import sqlalchemy as sa

revision = "036_drop_task_deadline_start"
down_revision = "035_add_task_performance_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Remove deadline_start column and index."""
    op.drop_index("idx_tasks_deadline_start", table_name="tasks")
    op.drop_column("tasks", "deadline_start")


def downgrade() -> None:
    """Re-add deadline_start column and index."""
    op.add_column("tasks", sa.Column("deadline_start", sa.Date(), nullable=True))
    op.create_index("idx_tasks_deadline_start", "tasks", ["deadline_start"])
