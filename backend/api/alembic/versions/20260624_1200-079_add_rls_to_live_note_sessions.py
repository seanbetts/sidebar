"""Enable RLS for live note sessions.

Revision ID: 079_add_rls_to_live_note_sessions
Revises: 078_add_live_notes
Create Date: 2026-06-24 12:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "079_add_rls_to_live_note_sessions"
down_revision: str | None = "078_add_live_notes"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP_USER = "(SELECT current_setting('app.user_id', true))"


def upgrade() -> None:
    """Enable RLS and restrict live note sessions to the scoped user."""
    op.execute("ALTER TABLE live_note_sessions ENABLE ROW LEVEL SECURITY")
    op.execute(
        "DROP POLICY IF EXISTS live_note_sessions_user_isolation "
        "ON live_note_sessions"
    )
    op.execute(
        f"""
        CREATE POLICY live_note_sessions_user_isolation
        ON live_note_sessions
        USING (user_id = {APP_USER})
        WITH CHECK (user_id = {APP_USER})
        """
    )


def downgrade() -> None:
    """Remove the live note sessions RLS policy."""
    op.execute(
        "DROP POLICY IF EXISTS live_note_sessions_user_isolation "
        "ON live_note_sessions"
    )
    op.execute("ALTER TABLE live_note_sessions DISABLE ROW LEVEL SECURITY")
