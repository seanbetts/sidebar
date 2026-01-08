"""Repair missing RLS on tables.

Revision ID: 030_repair_missing_rls
Revises: 029_add_rls_to_things_bridge_install_tokens
Create Date: 2026-01-07 16:10:00
"""

from alembic import op

revision = "030_repair_missing_rls"
down_revision = "029_add_rls_to_things_bridge_install_tokens"
branch_labels = None
depends_on = None


TABLES_NEEDING_RLS = [
    "conversations",
    "file_derivatives",
    "file_processing_jobs",
    "ingested_files",
    "notes",
    "things_bridges",
    "user_memories",
    "user_settings",
    "website_processing_jobs",
    "websites",
]


def upgrade() -> None:
    """Enable RLS on tables that are missing it."""
    for table in TABLES_NEEDING_RLS:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")


def downgrade() -> None:
    """Disable RLS on these tables."""
    for table in TABLES_NEEDING_RLS:
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")
