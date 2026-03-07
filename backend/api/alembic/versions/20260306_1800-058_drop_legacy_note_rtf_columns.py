"""Drop legacy note RTF columns after semantic-document migration.

Revision ID: 058_drop_legacy_note_rtf_columns
Revises: 057_add_semantic_note_document
Create Date: 2026-03-06 18:00:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "058_drop_legacy_note_rtf_columns"
down_revision: str | None = "057_add_semantic_note_document"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Backfill semantic documents, require them, and drop legacy RTF columns."""
    op.execute(
        "UPDATE notes "
        "SET document = jsonb_build_object("
        "    'version', 1, "
        "    'blocks', jsonb_build_array("
        "        jsonb_build_object("
        "            'type', 'paragraph', "
        "            'content', jsonb_build_array("
        "                jsonb_build_object("
        "                    'text', COALESCE(plain_text, ''), "
        "                    'marks', jsonb_build_array()"
        "                )"
        "            )"
        "        )"
        "    )"
        ") "
        "WHERE document IS NULL OR jsonb_typeof(document) = 'null'"
    )
    op.execute("ALTER TABLE notes ALTER COLUMN document SET NOT NULL")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS content")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS content_format")


def downgrade() -> None:
    """Restore legacy note RTF columns and relax semantic document requirement."""
    op.execute(
        "ALTER TABLE notes ADD COLUMN IF NOT EXISTS content text NOT NULL DEFAULT ''"
    )
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS content_format text NOT NULL DEFAULT 'rtf'"
    )
    op.execute("ALTER TABLE notes ALTER COLUMN document DROP NOT NULL")
