"""Remove legacy inbox task status.

Revision ID: 061_remove_task_inbox_status
Revises: 060_remove_legacy_skill_arrays
Create Date: 2026-03-08 15:00:00.000000
"""

from __future__ import annotations

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "061_remove_task_inbox_status"
down_revision: str | None = "060_remove_legacy_skill_arrays"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    """Normalize legacy inbox task rows to the active status."""
    op.execute("UPDATE tasks SET status = 'active' WHERE status = 'inbox'")
    op.execute("ALTER TABLE tasks ALTER COLUMN status SET DEFAULT 'active'")


def downgrade() -> None:
    """Restore the legacy inbox default and rows for rollback."""
    op.execute("UPDATE tasks SET status = 'inbox' WHERE status = 'active'")
    op.execute("ALTER TABLE tasks ALTER COLUMN status SET DEFAULT 'inbox'")
