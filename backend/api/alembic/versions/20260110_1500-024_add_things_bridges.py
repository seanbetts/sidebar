"""Add things bridges table.

Revision ID: 024_add_things_bridges
Revises: 023_add_realtime_select_policies
Create Date: 2026-01-10 15:00:00
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "024_add_things_bridges"
down_revision = "023_add_realtime_select_policies"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "things_bridges",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("device_id", sa.Text(), nullable=False),
        sa.Column("device_name", sa.Text(), nullable=False),
        sa.Column("base_url", sa.Text(), nullable=False),
        sa.Column("bridge_token", sa.Text(), nullable=False),
        sa.Column("capabilities", postgresql.JSONB(), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("user_id", "device_id", name="uq_things_bridges_user_device"),
    )
    op.create_index("idx_things_bridges_user_id", "things_bridges", ["user_id"])
    op.create_index("idx_things_bridges_last_seen", "things_bridges", ["last_seen_at"])
    op.execute("ALTER TABLE things_bridges ENABLE ROW LEVEL SECURITY")
    op.execute("DROP POLICY IF EXISTS things_bridges_user_isolation ON things_bridges")
    op.execute(
        """
        CREATE POLICY things_bridges_user_isolation
        ON things_bridges
        USING (user_id = current_setting('app.user_id', true))
        WITH CHECK (user_id = current_setting('app.user_id', true))
        """
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS things_bridges_user_isolation ON things_bridges")
    op.execute("ALTER TABLE things_bridges DISABLE ROW LEVEL SECURITY")
    op.drop_index("idx_things_bridges_last_seen", table_name="things_bridges")
    op.drop_index("idx_things_bridges_user_id", table_name="things_bridges")
    op.drop_table("things_bridges")
