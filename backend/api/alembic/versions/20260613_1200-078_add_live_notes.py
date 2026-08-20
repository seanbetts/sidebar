"""Add live note session sync table.

Revision ID: 078_add_live_notes
Revises: 077_grant_realtime_table_select
Create Date: 2026-06-13 12:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "078_add_live_notes"
down_revision: str | None = "077_grant_realtime_table_select"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

APP_USER = "(SELECT current_setting('app.user_id', true))"


def upgrade() -> None:
    """Create the live note session sync table and indexes."""
    op.create_table(
        "live_note_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column(
            "note_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("notes.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("client_session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column(
            "transcript_segments",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "generated_sections",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "route_metadata",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("last_processed_range", postgresql.JSONB(), nullable=True),
        sa.Column("failure_state", postgresql.JSONB(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.execute("ALTER TABLE live_note_sessions ENABLE ROW LEVEL SECURITY")
    op.execute(
        "DROP POLICY IF EXISTS live_note_sessions_user_isolation "
        "ON live_note_sessions"
    )
    op.execute(
        f"""
        CREATE POLICY live_note_sessions_user_isolation
        ON live_note_sessions
        USING (user_id = {APP_USER})
        WITH CHECK (user_id = {APP_USER})
        """
    )
    op.create_index(
        "idx_live_note_sessions_user_id", "live_note_sessions", ["user_id"]
    )
    op.create_index(
        "idx_live_note_sessions_note_id", "live_note_sessions", ["note_id"]
    )
    op.create_index(
        "idx_live_note_sessions_client_session_id",
        "live_note_sessions",
        ["client_session_id"],
    )
    op.create_index(
        "idx_live_note_sessions_created_at", "live_note_sessions", ["created_at"]
    )
    op.create_index(
        "idx_live_note_sessions_updated_at", "live_note_sessions", ["updated_at"]
    )
    op.create_index(
        "idx_live_note_sessions_deleted_at", "live_note_sessions", ["deleted_at"]
    )
    op.create_index(
        "idx_live_note_sessions_user_updated",
        "live_note_sessions",
        ["user_id", "updated_at"],
    )
    op.create_index(
        "idx_live_note_sessions_user_note",
        "live_note_sessions",
        ["user_id", "note_id"],
    )
    op.create_index(
        "idx_live_note_sessions_deleted", "live_note_sessions", ["deleted_at"]
    )
    op.create_index(
        "uq_live_note_sessions_user_client_active",
        "live_note_sessions",
        ["user_id", "client_session_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    """Drop the live note session sync table."""
    op.execute(
        "DROP POLICY IF EXISTS live_note_sessions_user_isolation "
        "ON live_note_sessions"
    )
    op.drop_index(
        "uq_live_note_sessions_user_client_active",
        table_name="live_note_sessions",
    )
    op.drop_index("idx_live_note_sessions_deleted", table_name="live_note_sessions")
    op.drop_index("idx_live_note_sessions_user_note", table_name="live_note_sessions")
    op.drop_index(
        "idx_live_note_sessions_user_updated", table_name="live_note_sessions"
    )
    op.drop_index("idx_live_note_sessions_deleted_at", table_name="live_note_sessions")
    op.drop_index("idx_live_note_sessions_updated_at", table_name="live_note_sessions")
    op.drop_index("idx_live_note_sessions_created_at", table_name="live_note_sessions")
    op.drop_index(
        "idx_live_note_sessions_client_session_id", table_name="live_note_sessions"
    )
    op.drop_index("idx_live_note_sessions_note_id", table_name="live_note_sessions")
    op.drop_index("idx_live_note_sessions_user_id", table_name="live_note_sessions")
    op.drop_table("live_note_sessions")
