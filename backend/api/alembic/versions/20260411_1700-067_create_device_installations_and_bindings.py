"""Create installation-backed push tables and backfill legacy device tokens.

Revision ID: 067_create_device_installations_and_bindings
Revises: 066_backfill_device_token_notification_defaults
Create Date: 2026-04-11 17:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "067_create_device_installations_and_bindings"
down_revision: str | None = "066_backfill_device_token_notification_defaults"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create installation tables and backfill from legacy user-owned tokens."""
    op.create_table(
        "device_installations",
        sa.Column(
            "id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False
        ),
        sa.Column("installation_id", sa.Text(), nullable=False),
        sa.Column("token", sa.Text(), nullable=False),
        sa.Column("platform", sa.Text(), nullable=False),
        sa.Column("environment", sa.Text(), nullable=False),
        sa.Column(
            "capabilities",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "is_foreground",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "uq_device_installations_active_installation_id",
        "device_installations",
        ["installation_id"],
        unique=True,
        postgresql_where=sa.text("disabled_at IS NULL"),
    )
    op.create_index(
        "uq_device_installations_active_token",
        "device_installations",
        ["token"],
        unique=True,
        postgresql_where=sa.text("disabled_at IS NULL"),
    )
    op.create_index(
        "idx_device_installations_platform",
        "device_installations",
        ["platform"],
    )
    op.create_index(
        "idx_device_installations_environment",
        "device_installations",
        ["environment"],
    )
    op.create_index(
        "idx_device_installations_disabled_at",
        "device_installations",
        ["disabled_at"],
    )

    op.create_table(
        "device_installation_users",
        sa.Column(
            "id", postgresql.UUID(as_uuid=True), primary_key=True, nullable=False
        ),
        sa.Column(
            "installation_pk",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("device_installations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("bound_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("unbound_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "idx_device_installation_users_user_id",
        "device_installation_users",
        ["user_id"],
    )
    op.create_index(
        "idx_device_installation_users_installation_pk",
        "device_installation_users",
        ["installation_pk"],
    )
    op.create_index(
        "uq_device_installation_users_active_installation",
        "device_installation_users",
        ["installation_pk"],
        unique=True,
        postgresql_where=sa.text("unbound_at IS NULL"),
    )

    op.execute(
        """
        INSERT INTO device_installations (
            id,
            installation_id,
            token,
            platform,
            environment,
            capabilities,
            is_foreground,
            last_seen_at,
            created_at,
            updated_at,
            disabled_at
        )
        SELECT
            id,
            token,
            token,
            platform,
            environment,
            COALESCE(capabilities, '{}'::jsonb),
            COALESCE(is_foreground, false),
            last_seen_at,
            created_at,
            updated_at,
            disabled_at
        FROM device_tokens
        """
    )

    op.execute(
        """
        INSERT INTO device_installation_users (
            id,
            installation_pk,
            user_id,
            bound_at,
            unbound_at,
            created_at,
            updated_at
        )
        SELECT
            id,
            id,
            user_id,
            created_at,
            disabled_at,
            created_at,
            updated_at
        FROM device_tokens
        """
    )

    op.alter_column(
        "device_installations",
        "capabilities",
        server_default=None,
        existing_type=postgresql.JSONB(astext_type=sa.Text()),
    )
    op.alter_column(
        "device_installations",
        "is_foreground",
        server_default=None,
        existing_type=sa.Boolean(),
    )


def downgrade() -> None:
    """Drop installation-backed push tables."""
    op.drop_index(
        "uq_device_installation_users_active_installation",
        table_name="device_installation_users",
    )
    op.drop_index(
        "idx_device_installation_users_installation_pk",
        table_name="device_installation_users",
    )
    op.drop_index(
        "idx_device_installation_users_user_id",
        table_name="device_installation_users",
    )
    op.drop_table("device_installation_users")

    op.drop_index(
        "idx_device_installations_disabled_at",
        table_name="device_installations",
    )
    op.drop_index(
        "idx_device_installations_environment",
        table_name="device_installations",
    )
    op.drop_index(
        "idx_device_installations_platform",
        table_name="device_installations",
    )
    op.drop_index(
        "uq_device_installations_active_token",
        table_name="device_installations",
    )
    op.drop_index(
        "uq_device_installations_active_installation_id",
        table_name="device_installations",
    )
    op.drop_table("device_installations")
