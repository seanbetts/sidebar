"""Add generated is_archived column to notes.

Revision ID: 041_add_notes_is_archived
Revises: 040_add_ingested_files_updated_at
Create Date: 2026-01-31 15:30:00
"""

from collections.abc import Sequence

from alembic import op

revision: str = "041_add_notes_is_archived"
down_revision: str | None = "040_add_ingested_files_updated_at"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add generated is_archived column for notes."""
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS is_archived boolean "
        "GENERATED ALWAYS AS ("
        "(COALESCE(metadata->>'archived','false') = 'true') "
        "OR (COALESCE(metadata->>'folder','') = 'Archive') "
        "OR (COALESCE(metadata->>'folder','') LIKE 'Archive/%')"
        ") STORED"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_user_archived_updated "
        "ON notes (user_id, is_archived, updated_at DESC) "
        "WHERE deleted_at IS NULL"
    )


def downgrade() -> None:
    """Remove generated is_archived column for notes."""
    op.execute("DROP INDEX IF EXISTS idx_notes_user_archived_updated")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS is_archived")
