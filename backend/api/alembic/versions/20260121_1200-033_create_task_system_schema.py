"""Create native task system schema.

Revision ID: 033_create_task_system_schema
Revises: 032_fix_multiple_policies
Create Date: 2026-01-21 12:00:00
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "033_create_task_system_schema"
down_revision = "032_fix_multiple_policies"
branch_labels = None
depends_on = None


USER_ISOLATION_POLICY = """
CREATE POLICY {policy}
ON {table}
USING (user_id = current_setting('app.user_id', true))
WITH CHECK (user_id = current_setting('app.user_id', true))
"""


def upgrade() -> None:
    """Create task system tables with RLS policies."""
    op.create_table(
        "task_areas",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("things_id", sa.Text(), nullable=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("user_id", "things_id", name="uq_task_areas_user_things"),
    )
    op.create_index("idx_task_areas_user_id", "task_areas", ["user_id"])
    op.create_index("idx_task_areas_deleted_at", "task_areas", ["deleted_at"])

    op.create_table(
        "task_projects",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("things_id", sa.Text(), nullable=True),
        sa.Column("area_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="active"),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["area_id"], ["task_areas.id"], name="fk_task_projects_area_id"),
        sa.UniqueConstraint("user_id", "things_id", name="uq_task_projects_user_things"),
    )
    op.create_index("idx_task_projects_user_id", "task_projects", ["user_id"])
    op.create_index("idx_task_projects_area_id", "task_projects", ["area_id"])
    op.create_index("idx_task_projects_status", "task_projects", ["status"])
    op.create_index(
        "idx_task_projects_deleted_at", "task_projects", ["deleted_at"]
    )

    op.create_table(
        "tasks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("things_id", sa.Text(), nullable=True),
        sa.Column("project_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("area_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("status", sa.Text(), nullable=False, server_default="inbox"),
        sa.Column("deadline", sa.Date(), nullable=True),
        sa.Column("deadline_start", sa.Date(), nullable=True),
        sa.Column("scheduled_date", sa.Date(), nullable=True),
        sa.Column("repeating", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column(
            "repeat_template",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column("repeat_template_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("recurrence_rule", postgresql.JSONB(), nullable=True),
        sa.Column("next_instance_date", sa.Date(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("trashed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["project_id"], ["task_projects.id"], name="fk_tasks_project_id"),
        sa.ForeignKeyConstraint(["area_id"], ["task_areas.id"], name="fk_tasks_area_id"),
        sa.ForeignKeyConstraint(
            ["repeat_template_id"], ["tasks.id"], name="fk_tasks_repeat_template_id"
        ),
        sa.UniqueConstraint("user_id", "things_id", name="uq_tasks_user_things"),
    )
    op.create_index("idx_tasks_user_id", "tasks", ["user_id"])
    op.create_index("idx_tasks_project_id", "tasks", ["project_id"])
    op.create_index("idx_tasks_area_id", "tasks", ["area_id"])
    op.create_index("idx_tasks_status", "tasks", ["status"])
    op.create_index("idx_tasks_deadline", "tasks", ["deadline"])
    op.create_index("idx_tasks_deadline_start", "tasks", ["deadline_start"])
    op.create_index("idx_tasks_scheduled_date", "tasks", ["scheduled_date"])
    op.create_index("idx_tasks_completed_at", "tasks", ["completed_at"])
    op.create_index("idx_tasks_next_instance_date", "tasks", ["next_instance_date"])
    op.create_index("idx_tasks_deleted_at", "tasks", ["deleted_at"])
    op.create_index("idx_tasks_repeat_template_id", "tasks", ["repeat_template_id"])
    op.create_index("idx_tasks_user_status", "tasks", ["user_id", "status"])
    op.create_index(
        "uq_tasks_repeat_template_date",
        "tasks",
        ["repeat_template_id", "scheduled_date"],
        unique=True,
        postgresql_where=sa.text("repeat_template_id IS NOT NULL"),
    )

    op.create_table(
        "task_operation_log",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("operation_id", sa.Text(), nullable=False),
        sa.Column("operation_type", sa.Text(), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint(
            "user_id", "operation_id", name="uq_task_operation_log_user_operation"
        ),
    )
    op.create_index("idx_task_operation_log_user_id", "task_operation_log", ["user_id"])
    op.create_index(
        "idx_task_operation_log_operation_id",
        "task_operation_log",
        ["operation_id"],
    )

    for table, policy in (
        ("task_areas", "task_areas_user_isolation"),
        ("task_projects", "task_projects_user_isolation"),
        ("tasks", "tasks_user_isolation"),
        ("task_operation_log", "task_operation_log_user_isolation"),
    ):
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"DROP POLICY IF EXISTS {policy} ON {table}")
        op.execute(USER_ISOLATION_POLICY.format(policy=policy, table=table))


def downgrade() -> None:
    """Drop task system tables and RLS policies."""
    for table, policy in (
        ("task_operation_log", "task_operation_log_user_isolation"),
        ("tasks", "tasks_user_isolation"),
        ("task_projects", "task_projects_user_isolation"),
        ("task_areas", "task_areas_user_isolation"),
    ):
        op.execute(f"DROP POLICY IF EXISTS {policy} ON {table}")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")

    op.drop_index("idx_task_operation_log_operation_id", table_name="task_operation_log")
    op.drop_index("idx_task_operation_log_user_id", table_name="task_operation_log")
    op.drop_table("task_operation_log")

    op.drop_index("uq_tasks_repeat_template_date", table_name="tasks")
    op.drop_index("idx_tasks_user_status", table_name="tasks")
    op.drop_index("idx_tasks_repeat_template_id", table_name="tasks")
    op.drop_index("idx_tasks_deleted_at", table_name="tasks")
    op.drop_index("idx_tasks_next_instance_date", table_name="tasks")
    op.drop_index("idx_tasks_completed_at", table_name="tasks")
    op.drop_index("idx_tasks_scheduled_date", table_name="tasks")
    op.drop_index("idx_tasks_deadline_start", table_name="tasks")
    op.drop_index("idx_tasks_deadline", table_name="tasks")
    op.drop_index("idx_tasks_status", table_name="tasks")
    op.drop_index("idx_tasks_area_id", table_name="tasks")
    op.drop_index("idx_tasks_project_id", table_name="tasks")
    op.drop_index("idx_tasks_user_id", table_name="tasks")
    op.drop_table("tasks")

    op.drop_index("idx_task_projects_deleted_at", table_name="task_projects")
    op.drop_index("idx_task_projects_status", table_name="task_projects")
    op.drop_index("idx_task_projects_area_id", table_name="task_projects")
    op.drop_index("idx_task_projects_user_id", table_name="task_projects")
    op.drop_table("task_projects")

    op.drop_index("idx_task_areas_deleted_at", table_name="task_areas")
    op.drop_index("idx_task_areas_user_id", table_name="task_areas")
    op.drop_table("task_areas")
