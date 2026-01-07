"""Add RLS to things_bridge_install_tokens table.

Revision ID: 029_add_rls_to_things_bridge_install_tokens
Revises: 028_add_rls_to_alembic_version
Create Date: 2026-01-07 16:05:00
"""

from alembic import op

revision = "029_add_rls_to_things_bridge_install_tokens"
down_revision = "028_add_rls_to_alembic_version"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Enable RLS on things_bridge_install_tokens table
    op.execute("ALTER TABLE things_bridge_install_tokens ENABLE ROW LEVEL SECURITY")

    # Allow users to view only their own tokens
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_select
        ON things_bridge_install_tokens
        FOR SELECT
        USING (user_id = auth.uid()::text)
        """
    )

    # Allow users to insert their own tokens
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_insert
        ON things_bridge_install_tokens
        FOR INSERT
        WITH CHECK (user_id = auth.uid()::text)
        """
    )

    # Allow users to update their own tokens (e.g., marking as used)
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_update
        ON things_bridge_install_tokens
        FOR UPDATE
        USING (user_id = auth.uid()::text)
        WITH CHECK (user_id = auth.uid()::text)
        """
    )

    # Allow users to delete their own tokens
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_delete
        ON things_bridge_install_tokens
        FOR DELETE
        USING (user_id = auth.uid()::text)
        """
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS things_bridge_install_tokens_select ON things_bridge_install_tokens")
    op.execute("DROP POLICY IF EXISTS things_bridge_install_tokens_insert ON things_bridge_install_tokens")
    op.execute("DROP POLICY IF EXISTS things_bridge_install_tokens_update ON things_bridge_install_tokens")
    op.execute("DROP POLICY IF EXISTS things_bridge_install_tokens_delete ON things_bridge_install_tokens")
    op.execute("ALTER TABLE things_bridge_install_tokens DISABLE ROW LEVEL SECURITY")
