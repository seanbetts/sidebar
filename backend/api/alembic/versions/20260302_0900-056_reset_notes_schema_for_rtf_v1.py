"""Reset notes schema for explicit rich-text columns.

Revision ID: 056_reset_notes_schema_for_rtf_v1
Revises: 055_prune_reclassified_store_skills
Create Date: 2026-03-02 09:00:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "056_reset_notes_schema_for_rtf_v1"
down_revision: str | None = "055_prune_reclassified_store_skills"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Reset notes storage to explicit v1 rich-text columns without data loss."""
    op.execute("DROP INDEX IF EXISTS idx_notes_metadata_folder")
    op.execute("DROP INDEX IF EXISTS idx_notes_metadata_pinned")
    op.execute("DROP INDEX IF EXISTS idx_notes_user_folder")
    op.execute("DROP INDEX IF EXISTS idx_notes_user_archived_updated")
    op.execute("DROP INDEX IF EXISTS idx_notes_user_pinned_order")

    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS is_archived")
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS plain_text text NOT NULL DEFAULT ''"
    )
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS content_format text NOT NULL DEFAULT 'rtf'"
    )
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS folder_path text NOT NULL DEFAULT ''"
    )
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS pinned boolean NOT NULL DEFAULT false"
    )
    op.execute("ALTER TABLE notes ADD COLUMN IF NOT EXISTS pinned_order integer")
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS is_folder_marker boolean NOT NULL DEFAULT false"
    )
    op.execute(
        "ALTER TABLE notes "
        "ADD COLUMN IF NOT EXISTS is_archived boolean NOT NULL DEFAULT false"
    )
    op.execute(
        "UPDATE notes SET "
        "plain_text = COALESCE(metadata->>'plain_text', plain_text, ''), "
        "content_format = COALESCE("
        "NULLIF(metadata->>'content_format', ''), "
        "content_format, "
        "'rtf'"
        "), "
        "folder_path = COALESCE(metadata->>'folder', folder_path, ''), "
        "pinned = CASE "
        "    WHEN metadata ? 'pinned' "
        "        THEN LOWER(COALESCE(metadata->>'pinned', 'false')) "
        "        IN ('true', 't', '1') "
        "    ELSE pinned "
        "END, "
        "pinned_order = CASE "
        "    WHEN metadata ? 'pinned_order' "
        "        AND (metadata->>'pinned_order') ~ '^-?\\d+$' "
        "        THEN (metadata->>'pinned_order')::integer "
        "    ELSE pinned_order "
        "END, "
        "is_folder_marker = CASE "
        "    WHEN metadata ? 'is_folder_marker' "
        "        THEN LOWER(COALESCE(metadata->>'is_folder_marker', 'false')) "
        "        IN ('true', 't', '1') "
        "    ELSE is_folder_marker "
        "END, "
        "is_archived = ("
        "    LOWER(COALESCE(metadata->>'archived', 'false')) IN ('true', 't', '1') "
        "    OR COALESCE(metadata->>'folder', '') = 'Archive' "
        "    OR COALESCE(metadata->>'folder', '') LIKE 'Archive/%'"
        ")"
    )

    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_user_folder "
        "ON notes (user_id, folder_path)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_user_archived_updated "
        "ON notes (user_id, is_archived, updated_at DESC) "
        "WHERE deleted_at IS NULL"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_user_pinned_order "
        "ON notes (user_id, pinned, pinned_order) "
        "WHERE deleted_at IS NULL"
    )


def downgrade() -> None:
    """Restore metadata-driven notes schema used before v1 reset."""
    op.execute("DROP INDEX IF EXISTS idx_notes_user_pinned_order")
    op.execute("DROP INDEX IF EXISTS idx_notes_user_archived_updated")
    op.execute("DROP INDEX IF EXISTS idx_notes_user_folder")

    op.execute(
        "UPDATE notes SET metadata = jsonb_strip_nulls("
        "    COALESCE(metadata, '{}'::jsonb) || jsonb_build_object("
        "        'plain_text', COALESCE(plain_text, ''), "
        "        'content_format', COALESCE(content_format, 'rtf'), "
        "        'folder', COALESCE(folder_path, ''), "
        "        'pinned', COALESCE(pinned, false), "
        "        'pinned_order', CASE "
        "            WHEN pinned_order IS NULL THEN 'null'::jsonb "
        "            ELSE to_jsonb(pinned_order) "
        "        END, "
        "        'is_folder_marker', COALESCE(is_folder_marker, false), "
        "        'archived', COALESCE(is_archived, false)"
        "    )"
        ")"
    )

    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS plain_text")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS content_format")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS folder_path")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS pinned")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS pinned_order")
    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS is_folder_marker")

    op.execute("ALTER TABLE notes DROP COLUMN IF EXISTS is_archived")
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
        "CREATE INDEX IF NOT EXISTS idx_notes_metadata_folder "
        "ON notes ((metadata->>'folder'))"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_metadata_pinned "
        "ON notes ((metadata->>'pinned'))"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS idx_notes_user_archived_updated "
        "ON notes (user_id, is_archived, updated_at DESC) "
        "WHERE deleted_at IS NULL"
    )
