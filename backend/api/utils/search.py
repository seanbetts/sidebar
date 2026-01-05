"""Search helpers for building common filter expressions."""
from __future__ import annotations

from typing import Iterable, Any

from sqlalchemy import or_


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
    search_term = f"%{query}%"
    if case_sensitive:
        return or_(*(field.like(search_term) for field in fields))
    return or_(*(field.ilike(search_term) for field in fields))
