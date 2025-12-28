"""Enable RLS policies for user-scoped tables."""

from alembic import op


revision = "012_enable_rls_policies"
down_revision = "011_add_notes_websites_user_id"
branch_labels = None
depends_on = None


POLICY_DEFS = [
    ("notes", "notes_user_isolation"),
    ("websites", "websites_user_isolation"),
    ("conversations", "conversations_user_isolation"),
    ("user_settings", "user_settings_user_isolation"),
    ("user_memories", "user_memories_user_isolation"),
]


def upgrade() -> None:
    """Enable RLS and create user isolation policies."""
    for table_name, policy_name in POLICY_DEFS:
        op.execute(f"ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY")
        op.execute(f"DROP POLICY IF EXISTS {policy_name} ON {table_name}")
        op.execute(
            f"""
            CREATE POLICY {policy_name}
            ON {table_name}
            USING (user_id = current_setting('app.user_id', true))
            WITH CHECK (user_id = current_setting('app.user_id', true))
            """
        )


def downgrade() -> None:
    """Drop policies and disable RLS on user-scoped tables."""
    for table_name, policy_name in POLICY_DEFS:
        op.execute(f"DROP POLICY IF EXISTS {policy_name} ON {table_name}")
        op.execute(f"ALTER TABLE {table_name} DISABLE ROW LEVEL SECURITY")
