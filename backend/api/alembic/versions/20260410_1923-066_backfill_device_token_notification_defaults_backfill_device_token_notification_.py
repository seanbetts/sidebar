"""Backfill device token notification defaults and enforce not-null.

Revision ID: 066_backfill_device_token_notification_defaults
Revises: 065_add_notification_preferences_and_device_token_metadata
Create Date: 2026-04-10 19:23:32.431696

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = "066_backfill_device_token_notification_defaults"
down_revision: Union[str, None] = "065_add_notification_preferences_and_device_token_metadata"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Normalize historical nullable rows before enforcing stricter fields."""
    op.execute(
        "UPDATE device_tokens SET capabilities = '{}'::jsonb WHERE capabilities IS NULL"
    )
    op.execute(
        "UPDATE device_tokens SET is_foreground = false WHERE is_foreground IS NULL"
    )

    op.alter_column(
        "device_tokens",
        "capabilities",
        existing_type=postgresql.JSONB(astext_type=sa.Text()),
        nullable=False,
    )
    op.alter_column(
        "device_tokens",
        "is_foreground",
        existing_type=sa.Boolean(),
        nullable=False,
    )


def downgrade() -> None:
    """Relax the stricter device token contract."""
    op.alter_column(
        "device_tokens",
        "is_foreground",
        existing_type=sa.Boolean(),
        nullable=True,
    )
    op.alter_column(
        "device_tokens",
        "capabilities",
        existing_type=postgresql.JSONB(astext_type=sa.Text()),
        nullable=True,
    )
