"""Allow unscoped ingestion workers to claim jobs across users.

Revision ID: 046_allow_unscoped_ingestion_worker_claims
Revises: 045_add_user_settings_assistant_soul
Create Date: 2026-02-19 14:00:00
"""

from alembic import op

revision = "046_allow_unscoped_ingestion_worker_claims"
down_revision = "045_add_user_settings_assistant_soul"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Update ingestion RLS policies to support worker-wide claim scope."""
    op.execute(
        "DROP POLICY IF EXISTS ingested_files_select_optimized ON ingested_files"
    )
    op.execute(
        """
        CREATE POLICY ingested_files_select_optimized
        ON ingested_files
        FOR SELECT
        USING (
            user_id = (SELECT current_setting('app.user_id', true))
            OR user_id = (SELECT auth.uid()::text)
            OR (SELECT current_setting('app.ingestion_scope', true)) = 'all'
        )
        """
    )

    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_select_optimized ON file_processing_jobs"
    )
    op.execute(
        """
        CREATE POLICY file_processing_jobs_select_optimized
        ON file_processing_jobs
        FOR SELECT
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = (SELECT current_setting('app.user_id', true))
                   OR user_id = (SELECT auth.uid()::text)
            )
            OR (SELECT current_setting('app.ingestion_scope', true)) = 'all'
        )
        """
    )

    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_backend_update ON file_processing_jobs"
    )
    op.execute(
        """
        CREATE POLICY file_processing_jobs_backend_update
        ON file_processing_jobs
        FOR UPDATE
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = (SELECT current_setting('app.user_id', true))
            )
            OR (SELECT current_setting('app.ingestion_scope', true)) = 'all'
        )
        WITH CHECK (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = (SELECT current_setting('app.user_id', true))
            )
            OR (SELECT current_setting('app.ingestion_scope', true)) = 'all'
        )
        """
    )


def downgrade() -> None:
    """Restore original ingestion RLS policies."""
    op.execute(
        "DROP POLICY IF EXISTS ingested_files_select_optimized ON ingested_files"
    )
    op.execute(
        """
        CREATE POLICY ingested_files_select_optimized
        ON ingested_files
        FOR SELECT
        USING (
            user_id = (SELECT current_setting('app.user_id', true))
            OR user_id = (SELECT auth.uid()::text)
        )
        """
    )

    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_select_optimized ON file_processing_jobs"
    )
    op.execute(
        """
        CREATE POLICY file_processing_jobs_select_optimized
        ON file_processing_jobs
        FOR SELECT
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = (SELECT current_setting('app.user_id', true))
                   OR user_id = (SELECT auth.uid()::text)
            )
        )
        """
    )

    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_backend_update ON file_processing_jobs"
    )
    op.execute(
        """
        CREATE POLICY file_processing_jobs_backend_update
        ON file_processing_jobs
        FOR UPDATE
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = (select current_setting('app.user_id', true))
            )
        )
        WITH CHECK (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = (select current_setting('app.user_id', true))
            )
        )
        """
    )
