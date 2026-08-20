"""Merge live-notes and task-reminder migration branches.

Revision ID: 080_merge_live_notes_and_task_reminders
Revises: 079_add_rls_to_live_note_sessions, 078_add_task_reminder_delivery_states
Create Date: 2026-08-20 12:00:00
"""

from __future__ import annotations

from collections.abc import Sequence

revision: str = "080_merge_live_notes_and_task_reminders"
down_revision: tuple[str, str] = (
    "079_add_rls_to_live_note_sessions",
    "078_add_task_reminder_delivery_states",
)
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Join the two already-defined schema branches."""


def downgrade() -> None:
    """Split the merged lineage without changing either branch schema."""
