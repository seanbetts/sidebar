"""Add semantic note document columns alongside legacy RTF storage.

Revision ID: 057_add_semantic_note_document
Revises: 056_reset_notes_schema_for_rtf_v1
Create Date: 2026-03-06 12:00:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "057_add_semantic_note_document"
down_revision: str | None = "056_reset_notes_schema_for_rtf_v1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add semantic note document columns without removing legacy fields."""
    op.execute("ALTER TABLE notes " "ADD COLUMN IF NOT EXISTS document jsonb")
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS document_version integer NOT NULL DEFAULT 1"
    )


def downgrade() -> None:
    """Remove semantic note document columns."""
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS document_version")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS document")
