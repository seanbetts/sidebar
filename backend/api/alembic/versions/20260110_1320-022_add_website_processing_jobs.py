"""Add website processing jobs table.

Revision ID: 022_add_website_processing_jobs
Revises: 021_update_user_settings_rls_for_pat
Create Date: 2026-01-10 13:20:00
"""

import sqlalchemy as sa
from alembic import op

revision = "022_add_website_processing_jobs"
down_revision = "021_update_user_settings_rls_for_pat"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "website_processing_jobs",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("url", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="queued"),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("website_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("idx_website_jobs_user_id", "website_processing_jobs", ["user_id"])
    op.create_index("idx_website_jobs_status", "website_processing_jobs", ["status"])

    op.execute("ALTER TABLE website_processing_jobs ENABLE ROW LEVEL SECURITY")
    op.execute("DROP POLICY IF EXISTS website_processing_jobs_user_isolation ON website_processing_jobs")
    op.execute(
        """
        CREATE POLICY website_processing_jobs_user_isolation
        ON website_processing_jobs
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS website_processing_jobs_user_isolation ON website_processing_jobs")
    op.drop_index("idx_website_jobs_status", table_name="website_processing_jobs")
    op.drop_index("idx_website_jobs_user_id", table_name="website_processing_jobs")
    op.drop_table("website_processing_jobs")
