"""Grant authenticated select access for Realtime tables.

Revision ID: 077_grant_realtime_table_select
Revises: 076_add_rls_to_notification_diagnostics_tables
Create Date: 2026-05-15 12:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "077_grant_realtime_table_select"
down_revision: str | None = "076_add_rls_to_notification_diagnostics_tables"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

REALTIME_TABLES = (
    "notes",
    "websites",
    "ingested_files",
    "file_processing_jobs",
    "tasks",
    "task_projects",
    "task_groups",
)


def upgrade() -> None:
    """Expose Realtime tables to signed-in Supabase clients."""
    op.execute(
        f"""
        GRANT SELECT ON TABLE
          {_qualified_table_list()}
        TO authenticated
        """
    )


def downgrade() -> None:
    """Remove explicit signed-in Supabase client access for Realtime tables."""
    op.execute(
        f"""
        REVOKE SELECT ON TABLE
          {_qualified_table_list()}
        FROM authenticated
        """
    )


def _qualified_table_list() -> str:
    """Return the public-schema table list used by the grant statements."""
    return ",\n          ".join(f"public.{table}" for table in REALTIME_TABLES)
