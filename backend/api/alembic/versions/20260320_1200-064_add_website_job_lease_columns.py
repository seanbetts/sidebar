"""Add lease columns to website processing jobs.

Revision ID: 064_add_website_job_lease_columns
Revises: 063_add_rls_to_user_skill_states
Create Date: 2026-03-20 12:00:00
"""

import sqlalchemy as sa
from alembic import op

revision = "064_add_website_job_lease_columns"
down_revision = "063_add_rls_to_user_skill_states"
branch_labels = None
depends_on = None

REALTIME_PUBLICATION = "supabase_realtime"
WEBSITE_JOB_TABLE = "website_processing_jobs"


def _publication_exists(publication_name: str) -> bool:
    """Return whether the target Postgres publication exists."""
    bind = op.get_bind()
    return bool(
        bind.scalar(
            sa.text(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM pg_publication
                    WHERE pubname = :publication_name
                )
                """
            ),
            {"publication_name": publication_name},
        )
    )


def _alter_publication_if_exists(publication_name: str, statement: str) -> None:
    """Run publication DDL only in environments that provision the publication."""
    if _publication_exists(publication_name):
        op.execute(statement)


def upgrade() -> None:
    """Add lease columns, worker-scope RLS policy, and Realtime publication."""
    op.add_column(
        WEBSITE_JOB_TABLE,
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        WEBSITE_JOB_TABLE,
        sa.Column("worker_id", sa.Text(), nullable=True),
    )
    op.create_index(
        "idx_website_jobs_status_lease",
        WEBSITE_JOB_TABLE,
        ["status", "lease_expires_at"],
    )
    # Allow worker to claim jobs across all users
    op.execute(
        "DROP POLICY IF EXISTS website_processing_jobs_worker_scope "
        "ON website_processing_jobs"
    )
    op.execute(
        """
        CREATE POLICY website_processing_jobs_worker_scope
        ON website_processing_jobs
        USING (
            user_id = current_setting('app.user_id', true)
            OR current_setting('app.website_worker_scope', true) = 'all'
        )
        WITH CHECK (
            user_id = current_setting('app.user_id', true)
            OR current_setting('app.website_worker_scope', true) = 'all'
        )
        """
    )
    # Drop the old user-only policy
    op.execute(
        "DROP POLICY IF EXISTS website_processing_jobs_user_isolation "
        "ON website_processing_jobs"
    )
    # Enable Realtime for job status notifications
    _alter_publication_if_exists(
        REALTIME_PUBLICATION,
        f"ALTER PUBLICATION {REALTIME_PUBLICATION} ADD TABLE {WEBSITE_JOB_TABLE}",
    )


def downgrade() -> None:
    """Remove lease columns, restore user-only RLS policy, drop Realtime publication."""
    _alter_publication_if_exists(
        REALTIME_PUBLICATION,
        f"ALTER PUBLICATION {REALTIME_PUBLICATION} DROP TABLE {WEBSITE_JOB_TABLE}",
    )
    # Restore original user-only policy
    op.execute(
        "DROP POLICY IF EXISTS website_processing_jobs_worker_scope "
        "ON website_processing_jobs"
    )
    op.execute(
        """
        CREATE POLICY website_processing_jobs_user_isolation
        ON website_processing_jobs
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )
    op.drop_index("idx_website_jobs_status_lease", table_name=WEBSITE_JOB_TABLE)
    op.drop_column(WEBSITE_JOB_TABLE, "worker_id")
    op.drop_column(WEBSITE_JOB_TABLE, "lease_expires_at")
