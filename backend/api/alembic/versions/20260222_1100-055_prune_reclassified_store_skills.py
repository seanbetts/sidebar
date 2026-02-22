"""Prune reclassified standard skills from installed_store_skills.

Revision ID: 055_prune_reclassified_store_skills
Revises: 054_backfill_store_skill_state
Create Date: 2026-02-22 11:00:00.000000
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "055_prune_reclassified_store_skills"
down_revision: str | None = "054_backfill_store_skill_state"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

RECLASSIFIED_SKILL_IDS: set[str] = {
    "prompt-preview",
    "settings-other-preferences",
}


def _normalize_installed_store_skills(raw_value: Any) -> list[str]:
    """Normalize installed_store_skills and remove reclassified skill IDs."""
    if not isinstance(raw_value, list):
        return []

    normalized: list[str] = []
    seen: set[str] = set()
    for item in raw_value:
        if not isinstance(item, str):
            continue
        candidate = item.strip()
        if not candidate:
            continue
        if candidate in RECLASSIFIED_SKILL_IDS:
            continue
        if candidate in seen:
            continue
        normalized.append(candidate)
        seen.add(candidate)

    return normalized


def upgrade() -> None:
    """Remove reclassified skill IDs from installed_store_skills arrays."""
    connection = op.get_bind()
    rows = connection.execute(
        sa.text(
            "SELECT user_id, installed_store_skills "
            "FROM user_settings "
            "WHERE installed_store_skills IS NOT NULL"
        )
    ).mappings()

    for row in rows:
        user_id = str(row["user_id"])
        raw_installed = row["installed_store_skills"]
        normalized_installed = _normalize_installed_store_skills(raw_installed)
        if normalized_installed == raw_installed:
            continue

        connection.execute(
            sa.text(
                "UPDATE user_settings "
                "SET installed_store_skills = CAST(:installed_store_skills AS jsonb) "
                "WHERE user_id = :user_id"
            ),
            {
                "user_id": user_id,
                "installed_store_skills": json.dumps(normalized_installed),
            },
        )


def downgrade() -> None:
    """This data migration is intentionally irreversible."""
    # No-op: reclassified IDs are removed from user state.
    return None
