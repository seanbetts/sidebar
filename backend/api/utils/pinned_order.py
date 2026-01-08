"""Helpers for pinned order concurrency control."""

from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.orm import Session


def lock_pinned_order(db: Session, user_id: str, scope: str) -> None:
    """Acquire an advisory lock for pinned order updates."""
    lock_key = f"pinned_order:{scope}:{user_id}"
    db.execute(
        text("SELECT pg_advisory_xact_lock(hashtext(:key))"),
        {"key": lock_key},
    )
