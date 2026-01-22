"""Add task performance indexes.

Revision ID: 035_add_task_performance_indexes
Revises: 034_rename_things_fields
Create Date: 2026-01-23 12:00:00
"""

from alembic import op
import sqlalchemy as sa

revision = "035_add_task_performance_indexes"
down_revision = "034_rename_things_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add trigram and scope lookup indexes for tasks."""
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    op.create_index(
        "idx_tasks_today_lookup",
        "tasks",
        ["user_id", "status", "scheduled_date", "deadline"],
        postgresql_where=sa.text(
            "deleted_at IS NULL AND status NOT IN ('completed', 'trashed', 'someday')"
        ),
    )
    op.create_index(
        "idx_tasks_title_trgm",
        "tasks",
        ["title"],
        postgresql_using="gin",
        postgresql_ops={"title": "gin_trgm_ops"},
    )
    op.create_index(
        "idx_tasks_notes_trgm",
        "tasks",
        ["notes"],
        postgresql_using="gin",
        postgresql_ops={"notes": "gin_trgm_ops"},
    )


def downgrade() -> None:
    """Remove trigram and scope lookup indexes for tasks."""
    op.drop_index("idx_tasks_notes_trgm", table_name="tasks")
    op.drop_index("idx_tasks_title_trgm", table_name="tasks")
    op.drop_index("idx_tasks_today_lookup", table_name="tasks")
    op.execute("DROP EXTENSION IF EXISTS pg_trgm")
