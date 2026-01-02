"""Add realtime select policies using auth.uid().

Revision ID: 023_add_realtime_select_policies
Revises: 022_add_website_processing_jobs
Create Date: 2026-01-10 13:30:00
"""

from alembic import op

revision = "023_add_realtime_select_policies"
down_revision = "022_add_website_processing_jobs"
branch_labels = None
depends_on = None


POLICIES = [
    ("notes", "notes_realtime_select", "user_id = auth.uid()"),
    ("websites", "websites_realtime_select", "user_id = auth.uid()"),
    ("ingested_files", "ingested_files_realtime_select", "user_id = auth.uid()"),
]


def upgrade() -> None:
    for table, policy, predicate in POLICIES:
        op.execute(f"DROP POLICY IF EXISTS {policy} ON {table}")
        op.execute(
            f"""
            CREATE POLICY {policy}
            ON {table}
            FOR SELECT
            USING ({predicate})
            """
        )

    op.execute("DROP POLICY IF EXISTS file_processing_jobs_realtime_select ON file_processing_jobs")
    op.execute(
        """
        CREATE POLICY file_processing_jobs_realtime_select
        ON file_processing_jobs
        FOR SELECT
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = auth.uid()
            )
        )
        """
    )


def downgrade() -> None:
    for table, policy, _predicate in POLICIES:
        op.execute(f"DROP POLICY IF EXISTS {policy} ON {table}")

    op.execute("DROP POLICY IF EXISTS file_processing_jobs_realtime_select ON file_processing_jobs")
