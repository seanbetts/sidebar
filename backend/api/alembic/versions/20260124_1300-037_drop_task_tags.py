"""Drop tasks.tags.

Revision ID: 037_drop_task_tags
Revises: 036_drop_task_deadline_start
Create Date: 2026-01-24 13:00:00
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "037_drop_task_tags"
down_revision = "036_drop_task_deadline_start"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Remove tags column and index."""
    op.execute("DROP INDEX IF EXISTS idx_tasks_tags_gin")
    op.execute("ALTER TABLE tasks DROP COLUMN IF EXISTS tags")


def downgrade() -> None:
    """Re-add tags column and index."""
    op.add_column("tasks", sa.Column("tags", postgresql.JSONB(), nullable=True))
    op.create_index(
        "idx_tasks_tags_gin",
        "tasks",
        ["tags"],
        postgresql_using="gin",
    )
