"""Add normalized per-user skill state table.

Revision ID: 059_add_user_skill_states
Revises: 058_drop_legacy_note_rtf_columns
Create Date: 2026-03-07 15:00:00.000000
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "059_add_user_skill_states"
down_revision: str | None = "058_drop_legacy_note_rtf_columns"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SKILL_ID_ALIASES: dict[str, str] = {
    "fs": "files",
}

REQUIRED_SKILL_IDS: list[str] = [
    "assistant-identity",
    "assistant-soul",
    "product-feedback",
]

DEFAULT_ENABLED_SKILL_IDS: list[str] = [
    "assistant-identity",
    "assistant-soul",
    "product-feedback",
    "files",
    "notes",
    "tasks",
    "web-save",
    "web-search",
    "memory",
    "settings-profile-user",
    "ui-theme",
    "prompt-preview",
    "settings-other-preferences",
]

STORE_SKILL_IDS: set[str] = {
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
}

EXPOSED_SKILL_IDS: list[str] = DEFAULT_ENABLED_SKILL_IDS + [
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
]

EXPOSED_SKILL_ID_SET = set(EXPOSED_SKILL_IDS)


def _canonicalize_skill_id(raw_skill_id: str) -> str:
    """Return canonical skill ID, resolving known legacy aliases."""
    return SKILL_ID_ALIASES.get(raw_skill_id, raw_skill_id)


def _normalize_skill_list(
    raw_value: Any,
    *,
    allowed_ids: set[str],
    required_ids: Sequence[str] = (),
) -> list[str]:
    """Normalize a JSON skill list, preserving order and removing duplicates."""
    normalized: list[str] = []
    seen: set[str] = set()

    if isinstance(raw_value, list):
        for item in raw_value:
            if not isinstance(item, str):
                continue
            canonical_id = _canonicalize_skill_id(item.strip())
            if canonical_id in allowed_ids and canonical_id not in seen:
                normalized.append(canonical_id)
                seen.add(canonical_id)

    for required_id in required_ids:
        if required_id in allowed_ids and required_id not in seen:
            normalized.append(required_id)
            seen.add(required_id)

    return normalized


def _normalize_row_state(
    raw_enabled: Any,
    raw_installed: Any,
) -> tuple[list[str], list[str]]:
    """Return normalized enabled and installed skill lists for one settings row."""
    normalized_installed = _normalize_skill_list(
        raw_installed,
        allowed_ids=STORE_SKILL_IDS,
    )

    if raw_enabled is None:
        normalized_enabled = list(DEFAULT_ENABLED_SKILL_IDS)
        for skill_id in normalized_installed:
            if skill_id not in normalized_enabled:
                normalized_enabled.append(skill_id)
        return normalized_enabled, normalized_installed

    normalized_enabled = _normalize_skill_list(
        raw_enabled,
        allowed_ids=EXPOSED_SKILL_ID_SET,
        required_ids=REQUIRED_SKILL_IDS,
    )
    if raw_installed is None:
        normalized_installed = [
            skill_id for skill_id in normalized_enabled if skill_id in STORE_SKILL_IDS
        ]
    return normalized_enabled, normalized_installed


def _build_user_skill_state_rows(
    *,
    user_id: str,
    raw_enabled: Any,
    raw_installed: Any,
    created_at: Any,
    updated_at: Any,
) -> list[dict[str, Any]]:
    """Return normalized user_skill_states rows for one user_settings row."""
    normalized_enabled, normalized_installed = _normalize_row_state(
        raw_enabled,
        raw_installed,
    )
    installed_set = set(normalized_installed)
    row_skill_ids = list(normalized_enabled)
    for skill_id in normalized_installed:
        if skill_id not in row_skill_ids:
            row_skill_ids.append(skill_id)

    return [
        {
            "id": uuid.uuid4(),
            "user_id": user_id,
            "skill_id": skill_id,
            "enabled": skill_id in normalized_enabled,
            "installed": skill_id in installed_set,
            "metadata": json.dumps({}),
            "created_at": created_at,
            "updated_at": updated_at,
            "deleted_at": None,
        }
        for skill_id in row_skill_ids
    ]


def upgrade() -> None:
    """Create the normalized user_skill_states table and backfill legacy data."""
    op.create_table(
        "user_skill_states",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", sa.Text(), nullable=False),
        sa.Column("skill_id", sa.Text(), nullable=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("installed", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "metadata",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_user_skill_states_user_id",
        "user_skill_states",
        ["user_id"],
    )
    op.create_index(
        "idx_user_skill_states_skill_id",
        "user_skill_states",
        ["skill_id"],
    )
    op.create_index(
        "uq_user_skill_states_active_user_skill",
        "user_skill_states",
        ["user_id", "skill_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )

    connection = op.get_bind()
    rows = connection.execute(
        sa.text(
            "SELECT user_id, enabled_skills, installed_store_skills, "
            "created_at, updated_at "
            "FROM user_settings"
        )
    ).mappings()

    insert_rows: list[dict[str, Any]] = []
    for row in rows:
        insert_rows.extend(
            _build_user_skill_state_rows(
                user_id=str(row["user_id"]),
                raw_enabled=row["enabled_skills"],
                raw_installed=row["installed_store_skills"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
            )
        )

    if insert_rows:
        connection.execute(
            sa.text(
                "INSERT INTO user_skill_states "
                "(id, user_id, skill_id, enabled, installed, metadata, "
                "created_at, updated_at, deleted_at) "
                "VALUES ("
                ":id, :user_id, :skill_id, :enabled, :installed, "
                "CAST(:metadata AS jsonb), :created_at, :updated_at, :deleted_at"
                ")"
            ),
            insert_rows,
        )


def downgrade() -> None:
    """Drop the normalized user_skill_states table."""
    op.drop_index(
        "uq_user_skill_states_active_user_skill",
        table_name="user_skill_states",
    )
    op.drop_index("idx_user_skill_states_skill_id", table_name="user_skill_states")
    op.drop_index("idx_user_skill_states_user_id", table_name="user_skill_states")
    op.drop_table("user_skill_states")
