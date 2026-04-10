"""Add notification preferences and device token metadata.

Revision ID: 065_add_notification_preferences_and_device_token_metadata
Revises: 064_add_website_job_lease_columns
Create Date: 2026-04-10 12:00:00
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "065_add_notification_preferences_and_device_token_metadata"
down_revision = "064_add_website_job_lease_columns"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Persist notification preferences and richer device token metadata.

    This revision reflects the schema shape already applied in production.
    The stricter non-null contract for device token presence metadata is
    enforced in the follow-up 066 migration after data backfill.
    """
    op.add_column(
        "user_settings",
        sa.Column(
            "notification_preferences",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )

    op.add_column(
        "device_tokens",
        sa.Column(
            "capabilities",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )
    op.add_column(
        "device_tokens",
        sa.Column(
            "is_foreground",
            sa.Boolean(),
            nullable=True,
        ),
    )
    op.add_column(
        "device_tokens",
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    """Remove notification preferences and device token metadata."""
    op.drop_column("device_tokens", "last_seen_at")
    op.drop_column("device_tokens", "is_foreground")
    op.drop_column("device_tokens", "capabilities")
    op.drop_column("user_settings", "notification_preferences")
