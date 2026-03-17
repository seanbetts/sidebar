"""Search helpers for building common filter expressions."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from sqlalchemy import or_

LIKE_ESCAPE = "\\"


def escape_like_pattern(query: str) -> str:
    """Escape LIKE wildcard characters in a user-provided query."""
    return (
        query.replace(LIKE_ESCAPE, LIKE_ESCAPE * 2)
        .replace("%", f"{LIKE_ESCAPE}%")
        .replace("_", f"{LIKE_ESCAPE}_")
    )


def build_text_search_filter(
    fields: Iterable[Any],
    query: str,
    *,
    case_sensitive: bool = False,
):
    """Build a SQLAlchemy filter for text search across fields.

    Args:
        fields: SQLAlchemy columns or expressions to search.
        query: Search query string.
        case_sensitive: Whether to perform case-sensitive search.

    Returns:
        SQLAlchemy filter expression combining fields with OR.
    """
    search_term = f"%{escape_like_pattern(query)}%"
    if case_sensitive:
        return or_(*(field.like(search_term, escape=LIKE_ESCAPE) for field in fields))
    return or_(*(field.ilike(search_term, escape=LIKE_ESCAPE) for field in fields))
