"""Add recent activity indexes.

Revision ID: 027_add_recent_activity_indexes
Revises: 026_add_user_settings_things_snapshot
Create Date: 2026-01-05 12:00:00.000000
"""

from alembic import op

revision = "027_add_recent_activity_indexes"
down_revision = "026_add_user_settings_things_snapshot"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "idx_notes_user_last_opened",
        "notes",
        ["user_id", "last_opened_at"],
    )
    op.create_index(
        "idx_notes_user_deleted_opened",
        "notes",
        ["user_id", "deleted_at", "last_opened_at"],
    )
    op.create_index(
        "idx_websites_user_last_opened",
        "websites",
        ["user_id", "last_opened_at"],
    )
    op.create_index(
        "idx_websites_user_deleted_opened",
        "websites",
        ["user_id", "deleted_at", "last_opened_at"],
    )
    op.create_index(
        "idx_conversations_user_updated_at",
        "conversations",
        ["user_id", "updated_at"],
    )
    op.create_index(
        "idx_ingested_files_user_last_opened",
        "ingested_files",
        ["user_id", "last_opened_at"],
    )


def downgrade() -> None:
    op.drop_index("idx_ingested_files_user_last_opened", table_name="ingested_files")
    op.drop_index("idx_conversations_user_updated_at", table_name="conversations")
    op.drop_index("idx_websites_user_deleted_opened", table_name="websites")
    op.drop_index("idx_websites_user_last_opened", table_name="websites")
    op.drop_index("idx_notes_user_deleted_opened", table_name="notes")
    op.drop_index("idx_notes_user_last_opened", table_name="notes")
