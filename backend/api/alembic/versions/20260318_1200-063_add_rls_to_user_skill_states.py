"""Enable RLS for user_skill_states.

Revision ID: 063_add_rls_to_user_skill_states
Revises: 062_add_onboarding_state
Create Date: 2026-03-18 12:00:00.000000
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "063_add_rls_to_user_skill_states"
down_revision: str | None = "062_add_onboarding_state"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Enable RLS and restrict access to the scoped backend user."""
    op.execute("ALTER TABLE user_skill_states ENABLE ROW LEVEL SECURITY")
    op.execute(
        "DROP POLICY IF EXISTS user_skill_states_user_isolation " "ON user_skill_states"
    )
    op.execute(
        """
        CREATE POLICY user_skill_states_user_isolation
        ON user_skill_states
        USING (user_id = (SELECT current_setting('app.user_id', true)))
        WITH CHECK (user_id = (SELECT current_setting('app.user_id', true)))
        """
    )


def downgrade() -> None:
    """Remove the user_skill_states policy and disable RLS."""
    op.execute(
        "DROP POLICY IF EXISTS user_skill_states_user_isolation " "ON user_skill_states"
    )
    op.execute("ALTER TABLE user_skill_states DISABLE ROW LEVEL SECURITY")
