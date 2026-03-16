"""Backfill store-skill installation state and normalize legacy skill IDs.

Revision ID: 054_backfill_store_skill_state
Revises: 053_add_user_settings_installed_store_skills
Create Date: 2026-02-21 09:00:00.000000
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "054_backfill_store_skill_state"
down_revision: str | None = "053_add_user_settings_installed_store_skills"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SKILL_ID_ALIASES: dict[str, str] = {
    "fs": "files",
}

REQUIRED_SKILL_IDS: list[str] = [
    "assistant-identity",
    "assistant-soul",
]

STORE_SKILL_IDS: set[str] = {
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
    "prompt-preview",
    "settings-other-preferences",
}

# Mirrors the catalog v2 exposed set at migration time to preserve behavior
# for users with enabled_skills = null.
EXPOSED_SKILL_IDS: list[str] = [
    "assistant-identity",
    "assistant-soul",
    "files",
    "notes",
    "tasks",
    "web-save",
    "web-search",
    "memory",
    "settings-profile-user",
    "ui-theme",
    "audio-transcribe",
    "youtube-download",
    "youtube-transcribe",
    "subdomain-discover",
    "web-crawler-policy",
    "prompt-preview",
    "settings-other-preferences",
]

EXPOSED_SKILL_ID_SET = set(EXPOSED_SKILL_IDS)


def _canonicalize_skill_id(raw_skill_id: str) -> str:
    """Return the canonical skill ID for legacy aliases."""
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
    """Return normalized enabled/installed skill lists for one settings row."""
    if raw_enabled is None:
        # Preserve pre-cutover behavior:
        # null enabled_skills resolved to all exposed skills.
        normalized_enabled = list(EXPOSED_SKILL_IDS)
        normalized_installed = [
            skill for skill in EXPOSED_SKILL_IDS if skill in STORE_SKILL_IDS
        ]
        return normalized_enabled, normalized_installed

    normalized_enabled = _normalize_skill_list(
        raw_enabled,
        allowed_ids=EXPOSED_SKILL_ID_SET,
        required_ids=REQUIRED_SKILL_IDS,
    )

    if raw_installed is None:
        normalized_installed = [
            skill for skill in normalized_enabled if skill in STORE_SKILL_IDS
        ]
    else:
        normalized_installed = _normalize_skill_list(
            raw_installed,
            allowed_ids=STORE_SKILL_IDS,
        )
    return normalized_enabled, normalized_installed


def upgrade() -> None:
    """Backfill installed store skills and normalize legacy `fs` IDs."""
    connection = op.get_bind()
    rows = connection.execute(
        sa.text(
            "SELECT user_id, enabled_skills, installed_store_skills "
            "FROM user_settings"
        )
    ).mappings()

    for row in rows:
        user_id = str(row["user_id"])
        raw_enabled = row["enabled_skills"]
        raw_installed = row["installed_store_skills"]
        normalized_enabled, normalized_installed = _normalize_row_state(
            raw_enabled, raw_installed
        )

        connection.execute(
            sa.text(
                "UPDATE user_settings "
                "SET enabled_skills = CAST(:enabled_skills AS jsonb), "
                "installed_store_skills = CAST(:installed_store_skills AS jsonb) "
                "WHERE user_id = :user_id"
            ),
            {
                "user_id": user_id,
                "enabled_skills": json.dumps(normalized_enabled),
                "installed_store_skills": json.dumps(normalized_installed),
            },
        )


def downgrade() -> None:
    """This data migration is intentionally irreversible."""
    # No-op: this migration canonicalizes and backfills JSON content.
    return None
