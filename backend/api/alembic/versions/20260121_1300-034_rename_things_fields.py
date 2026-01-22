"""Rename legacy fields and drop bridge tables.

Revision ID: 034_rename_things_fields
Revises: 033_create_task_system_schema
Create Date: 2026-01-21 13:00:00
"""

from alembic import op
import sqlalchemy as sa

revision = "034_rename_things_fields"
down_revision = "033_create_task_system_schema"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Rename legacy columns to source/task naming and drop bridge tables."""
    op.drop_constraint("uq_task_areas_user_things", "task_areas", type_="unique")
    op.drop_constraint("uq_task_projects_user_things", "task_projects", type_="unique")
    op.drop_constraint("uq_tasks_user_things", "tasks", type_="unique")

    op.alter_column("task_areas", "things_id", new_column_name="source_id")
    op.alter_column("task_projects", "things_id", new_column_name="source_id")
    op.alter_column("tasks", "things_id", new_column_name="source_id")

    op.create_unique_constraint(
        "uq_task_areas_user_source", "task_areas", ["user_id", "source_id"]
    )
    op.create_unique_constraint(
        "uq_task_projects_user_source", "task_projects", ["user_id", "source_id"]
    )
    op.create_unique_constraint(
        "uq_tasks_user_source", "tasks", ["user_id", "source_id"]
    )

    op.alter_column(
        "user_settings", "things_ai_snapshot", new_column_name="tasks_ai_snapshot"
    )

    op.execute("DROP POLICY IF EXISTS things_bridges_user_isolation ON things_bridges")
    op.drop_index("idx_things_bridges_last_seen", table_name="things_bridges")
    op.drop_index("idx_things_bridges_user_id", table_name="things_bridges")
    op.drop_table("things_bridges")

    op.execute(
        "DROP POLICY IF EXISTS things_bridge_install_tokens_select ON things_bridge_install_tokens"
    )
    op.execute(
        "DROP POLICY IF EXISTS things_bridge_install_tokens_insert ON things_bridge_install_tokens"
    )
    op.execute(
        "DROP POLICY IF EXISTS things_bridge_install_tokens_update ON things_bridge_install_tokens"
    )
    op.execute(
        "DROP POLICY IF EXISTS things_bridge_install_tokens_delete ON things_bridge_install_tokens"
    )
    op.drop_index(
        "idx_things_bridge_install_token_hash",
        table_name="things_bridge_install_tokens",
    )
    op.drop_index(
        "idx_things_bridge_install_user_id",
        table_name="things_bridge_install_tokens",
    )
    op.drop_table("things_bridge_install_tokens")


def downgrade() -> None:
    """Restore legacy columns and bridge tables."""
    op.create_table(
        "things_bridges",
        sa.Column("id", sa.Text(), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("device_id", sa.Text(), nullable=False),
        sa.Column("bridge_token", sa.Text(), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "device_id", name="uq_things_bridges_user_device"),
    )
    op.create_index("idx_things_bridges_user_id", "things_bridges", ["user_id"])
    op.create_index("idx_things_bridges_last_seen", "things_bridges", ["last_seen_at"])
    op.execute("ALTER TABLE things_bridges ENABLE ROW LEVEL SECURITY")
    op.execute(
        """
        CREATE POLICY things_bridges_user_isolation
        ON things_bridges
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )

    op.create_table(
        "things_bridge_install_tokens",
        sa.Column("id", sa.Text(), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("token_hash", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "idx_things_bridge_install_user_id",
        "things_bridge_install_tokens",
        ["user_id"],
    )
    op.create_index(
        "idx_things_bridge_install_token_hash",
        "things_bridge_install_tokens",
        ["token_hash"],
    )
    op.execute("ALTER TABLE things_bridge_install_tokens ENABLE ROW LEVEL SECURITY")
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_select
        ON things_bridge_install_tokens
        FOR SELECT
        USING (user_id = auth.uid()::text)
        """
    )
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_insert
        ON things_bridge_install_tokens
        FOR INSERT
        WITH CHECK (user_id = auth.uid()::text)
        """
    )
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_update
        ON things_bridge_install_tokens
        FOR UPDATE
        USING (user_id = auth.uid()::text)
        WITH CHECK (user_id = auth.uid()::text)
        """
    )
    op.execute(
        """
        CREATE POLICY things_bridge_install_tokens_delete
        ON things_bridge_install_tokens
        FOR DELETE
        USING (user_id = auth.uid()::text)
        """
    )

    op.alter_column(
        "user_settings", "tasks_ai_snapshot", new_column_name="things_ai_snapshot"
    )

    op.drop_constraint("uq_task_areas_user_source", "task_areas", type_="unique")
    op.drop_constraint("uq_task_projects_user_source", "task_projects", type_="unique")
    op.drop_constraint("uq_tasks_user_source", "tasks", type_="unique")

    op.alter_column("task_areas", "source_id", new_column_name="things_id")
    op.alter_column("task_projects", "source_id", new_column_name="things_id")
    op.alter_column("tasks", "source_id", new_column_name="things_id")

    op.create_unique_constraint(
        "uq_task_areas_user_things", "task_areas", ["user_id", "things_id"]
    )
    op.create_unique_constraint(
        "uq_task_projects_user_things", "task_projects", ["user_id", "things_id"]
    )
    op.create_unique_constraint(
        "uq_tasks_user_things", "tasks", ["user_id", "things_id"]
    )
