"""Add per-user encrypted AI provider key storage.

Revision ID: 048_add_user_ai_provider_keys
Revises: 047_add_user_settings_ai_provider_preferences
Create Date: 2026-02-19 23:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "048_add_user_ai_provider_keys"
down_revision: str | None = "047_add_user_settings_ai_provider_preferences"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create user_ai_provider_keys table and active-key unique index."""
    op.create_table(
        "user_ai_provider_keys",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("provider", sa.Text(), nullable=False),
        sa.Column("encrypted_api_key", sa.Text(), nullable=False),
        sa.Column("key_last4", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_user_ai_provider_keys_user_id",
        "user_ai_provider_keys",
        ["user_id"],
    )
    op.create_index(
        "idx_user_ai_provider_keys_provider",
        "user_ai_provider_keys",
        ["provider"],
    )
    op.create_index(
        "uq_user_ai_provider_keys_active_user_provider",
        "user_ai_provider_keys",
        ["user_id", "provider"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )


def downgrade() -> None:
    """Drop user_ai_provider_keys table and indexes."""
    op.drop_index(
        "uq_user_ai_provider_keys_active_user_provider",
        table_name="user_ai_provider_keys",
    )
    op.drop_index(
        "idx_user_ai_provider_keys_provider", table_name="user_ai_provider_keys"
    )
    op.drop_index(
        "idx_user_ai_provider_keys_user_id", table_name="user_ai_provider_keys"
    )
    op.drop_table("user_ai_provider_keys")
