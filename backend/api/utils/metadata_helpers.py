"""Shared helpers for JSONB metadata operations."""

from __future__ import annotations

from typing import Any, Protocol

from sqlalchemy import Integer, case, cast, func
from sqlalchemy.orm import Session


class _HasMetadata(Protocol):
    metadata_: Any
    user_id: Any
    deleted_at: Any


def get_max_pinned_order(
    db: Session, model_class: type[_HasMetadata], user_id: str
) -> int:
    """Return the current max pinned_order for a user.

    Args:
        db: Database session.
        model_class: ORM model with metadata_ JSONB.
        user_id: Current user ID.

    Returns:
        Max pinned_order value, or -1 if none are present.
    """
    pinned_order_text = model_class.metadata_["pinned_order"].astext
    numeric_order = case(
        (pinned_order_text.op("~")(r"^-?\d+$"), cast(pinned_order_text, Integer)),
        else_=None,
    )
    result = (
        db.query(func.max(numeric_order))
        .filter(
            model_class.user_id == user_id,
            model_class.deleted_at.is_(None),
            model_class.metadata_["pinned"].astext == "true",
        )
        .scalar()
    )
    return int(result) if result is not None else -1
