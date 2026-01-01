"""Add file ingestion metadata tables."""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "014_add_file_ingestion_tables"
down_revision = "013_add_files_table"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create ingestion metadata tables with RLS policies and indexes."""
    op.create_table(
        "ingested_files",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("filename_original", sa.Text(), nullable=False),
        sa.Column("mime_original", sa.Text(), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("sha256", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("idx_ingested_files_user_id", "ingested_files", ["user_id"])
    op.create_index("idx_ingested_files_created_at", "ingested_files", ["created_at"])
    op.create_index("idx_ingested_files_deleted_at", "ingested_files", ["deleted_at"])

    op.create_table(
        "file_derivatives",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("file_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("ingested_files.id"), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("storage_key", sa.Text(), nullable=False),
        sa.Column("mime", sa.Text(), nullable=False),
        sa.Column("size_bytes", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("sha256", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("idx_file_derivatives_file_id", "file_derivatives", ["file_id"])
    op.create_index("idx_file_derivatives_kind", "file_derivatives", ["kind"])

    op.create_table(
        "file_processing_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("file_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("ingested_files.id"), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="queued"),
        sa.Column("stage", sa.Text(), nullable=True),
        sa.Column("error_code", sa.Text(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("attempts", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("worker_id", sa.Text(), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("idx_file_processing_jobs_file_id", "file_processing_jobs", ["file_id"])
    op.create_index("idx_file_processing_jobs_status", "file_processing_jobs", ["status"])
    op.create_index("idx_file_processing_jobs_lease_expires_at", "file_processing_jobs", ["lease_expires_at"])

    op.execute("ALTER TABLE ingested_files ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE file_derivatives ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE file_processing_jobs ENABLE ROW LEVEL SECURITY")

    op.execute("DROP POLICY IF EXISTS ingested_files_user_isolation ON ingested_files")
    op.execute(
        """
        CREATE POLICY ingested_files_user_isolation
        ON ingested_files
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )

    op.execute("DROP POLICY IF EXISTS file_derivatives_user_isolation ON file_derivatives")
    op.execute(
        """
        CREATE POLICY file_derivatives_user_isolation
        ON file_derivatives
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = current_setting('app.user_id', true)
            )
        )
        WITH CHECK (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = current_setting('app.user_id', true)
            )
        )
        """
    )

    op.execute("DROP POLICY IF EXISTS file_processing_jobs_user_isolation ON file_processing_jobs")
    op.execute(
        """
        CREATE POLICY file_processing_jobs_user_isolation
        ON file_processing_jobs
        USING (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = current_setting('app.user_id', true)
            )
        )
        WITH CHECK (
            file_id IN (
                SELECT id FROM ingested_files
                WHERE user_id = current_setting('app.user_id', true)
            )
        )
        """
    )


def downgrade() -> None:
    """Drop ingestion metadata tables, indexes, and policies."""
    op.execute("DROP POLICY IF EXISTS file_processing_jobs_user_isolation ON file_processing_jobs")
    op.execute("DROP POLICY IF EXISTS file_derivatives_user_isolation ON file_derivatives")
    op.execute("DROP POLICY IF EXISTS ingested_files_user_isolation ON ingested_files")

    op.execute("ALTER TABLE file_processing_jobs DISABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE file_derivatives DISABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE ingested_files DISABLE ROW LEVEL SECURITY")

    op.drop_index("idx_file_processing_jobs_lease_expires_at", table_name="file_processing_jobs")
    op.drop_index("idx_file_processing_jobs_status", table_name="file_processing_jobs")
    op.drop_index("idx_file_processing_jobs_file_id", table_name="file_processing_jobs")
    op.drop_table("file_processing_jobs")

    op.drop_index("idx_file_derivatives_kind", table_name="file_derivatives")
    op.drop_index("idx_file_derivatives_file_id", table_name="file_derivatives")
    op.drop_table("file_derivatives")

    op.drop_index("idx_ingested_files_deleted_at", table_name="ingested_files")
    op.drop_index("idx_ingested_files_created_at", table_name="ingested_files")
    op.drop_index("idx_ingested_files_user_id", table_name="ingested_files")
    op.drop_table("ingested_files")
