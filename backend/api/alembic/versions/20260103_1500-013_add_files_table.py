"""Add files metadata table for storage objects."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "013_add_files_table"
down_revision = "012_enable_rls_policies"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create files table with RLS policies and indexes."""
    op.create_table(
        "files",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("bucket_key", sa.Text(), nullable=False),
        sa.Column("size", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("content_type", sa.Text(), nullable=True),
        sa.Column("etag", sa.Text(), nullable=True),
        sa.Column("category", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.UniqueConstraint("user_id", "path", name="uq_files_user_id_path"),
    )
    op.create_index("idx_files_user_id", "files", ["user_id"])
    op.create_index("idx_files_user_id_path", "files", ["user_id", "path"])
    op.create_index("idx_files_created_at", "files", ["created_at"])
    op.create_index("idx_files_updated_at", "files", ["updated_at"])
    op.create_index("idx_files_deleted_at", "files", ["deleted_at"])

    op.execute("ALTER TABLE files ENABLE ROW LEVEL SECURITY")
    op.execute("DROP POLICY IF EXISTS files_user_isolation ON files")
    op.execute(
        """
        CREATE POLICY files_user_isolation
        ON files
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )


def downgrade() -> None:
    """Drop files table, indexes, and policies."""
    op.execute("DROP POLICY IF EXISTS files_user_isolation ON files")
    op.execute("ALTER TABLE files DISABLE ROW LEVEL SECURITY")

    op.drop_index("idx_files_deleted_at", table_name="files")
    op.drop_index("idx_files_updated_at", table_name="files")
    op.drop_index("idx_files_created_at", table_name="files")
    op.drop_index("idx_files_user_id_path", table_name="files")
    op.drop_index("idx_files_user_id", table_name="files")
    op.drop_table("files")
