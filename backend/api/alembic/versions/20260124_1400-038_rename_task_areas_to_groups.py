"""Rename task areas to groups.

Revision ID: 038_rename_task_areas_to_groups
Revises: 154690804b8a
Create Date: 2026-01-24 14:00:00
"""

from alembic import op

revision = "038_rename_task_areas_to_groups"
down_revision = "154690804b8a"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Rename task areas schema to task groups."""
    op.rename_table("task_areas", "task_groups")

    op.drop_constraint("uq_task_areas_user_source", "task_groups", type_="unique")
    op.create_unique_constraint(
        "uq_task_groups_user_source", "task_groups", ["user_id", "source_id"]
    )

    op.drop_index("idx_task_areas_user_id", table_name="task_groups")
    op.drop_index("idx_task_areas_deleted_at", table_name="task_groups")
    op.create_index("idx_task_groups_user_id", "task_groups", ["user_id"])
    op.create_index("idx_task_groups_deleted_at", "task_groups", ["deleted_at"])

    op.drop_constraint("fk_task_projects_area_id", "task_projects", type_="foreignkey")
    op.alter_column("task_projects", "area_id", new_column_name="group_id")
    op.create_foreign_key(
        "fk_task_projects_group_id",
        "task_projects",
        "task_groups",
        ["group_id"],
        ["id"],
    )
    op.drop_index("idx_task_projects_area_id", table_name="task_projects")
    op.create_index("idx_task_projects_group_id", "task_projects", ["group_id"])

    op.drop_constraint("fk_tasks_area_id", "tasks", type_="foreignkey")
    op.alter_column("tasks", "area_id", new_column_name="group_id")
    op.create_foreign_key(
        "fk_tasks_group_id",
        "tasks",
        "task_groups",
        ["group_id"],
        ["id"],
    )
    op.drop_index("idx_tasks_area_id", table_name="tasks")
    op.create_index("idx_tasks_group_id", "tasks", ["group_id"])

    op.execute(
        "ALTER POLICY task_areas_user_isolation ON task_groups RENAME TO task_groups_user_isolation"
    )


def downgrade() -> None:
    """Revert task groups schema to task areas."""
    op.execute(
        "ALTER POLICY task_groups_user_isolation ON task_groups RENAME TO task_areas_user_isolation"
    )

    op.drop_constraint("fk_tasks_group_id", "tasks", type_="foreignkey")
    op.alter_column("tasks", "group_id", new_column_name="area_id")
    op.create_foreign_key(
        "fk_tasks_area_id",
        "tasks",
        "task_areas",
        ["area_id"],
        ["id"],
    )
    op.drop_index("idx_tasks_group_id", table_name="tasks")
    op.create_index("idx_tasks_area_id", "tasks", ["area_id"])

    op.drop_constraint("fk_task_projects_group_id", "task_projects", type_="foreignkey")
    op.alter_column("task_projects", "group_id", new_column_name="area_id")
    op.create_foreign_key(
        "fk_task_projects_area_id",
        "task_projects",
        "task_areas",
        ["area_id"],
        ["id"],
    )
    op.drop_index("idx_task_projects_group_id", table_name="task_projects")
    op.create_index("idx_task_projects_area_id", "task_projects", ["area_id"])

    op.drop_index("idx_task_groups_deleted_at", table_name="task_groups")
    op.drop_index("idx_task_groups_user_id", table_name="task_groups")
    op.drop_constraint("uq_task_groups_user_source", "task_groups", type_="unique")
    op.create_unique_constraint(
        "uq_task_areas_user_source", "task_groups", ["user_id", "source_id"]
    )
    op.create_index("idx_task_areas_user_id", "task_groups", ["user_id"])
    op.create_index("idx_task_areas_deleted_at", "task_groups", ["deleted_at"])

    op.rename_table("task_groups", "task_areas")
