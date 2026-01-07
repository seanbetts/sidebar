"""Add RLS to alembic_version table.

Revision ID: 028_add_rls_to_alembic_version
Revises: 027_add_recent_activity_indexes
Create Date: 2026-01-07 16:00:00
"""

from alembic import op

revision = "028_add_rls_to_alembic_version"
down_revision = "027_add_recent_activity_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Enable RLS on alembic_version table
    op.execute("ALTER TABLE alembic_version ENABLE ROW LEVEL SECURITY")

    # Create policy that denies all access (only backend migrations should access this)
    op.execute(
        """
        CREATE POLICY alembic_version_no_access
        ON alembic_version
        FOR ALL
        USING (false)
        """
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS alembic_version_no_access ON alembic_version")
    op.execute("ALTER TABLE alembic_version DISABLE ROW LEVEL SECURITY")
