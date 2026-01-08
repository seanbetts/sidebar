"""Generic workspace service abstractions."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Generic, TypeVar

from sqlalchemy.orm import Session

T = TypeVar("T")


class WorkspaceService(ABC, Generic[T]):
    """Base class for workspace-facing services."""

    @classmethod
    @abstractmethod
    def _query_items(
        cls,
        db: Session,
        user_id: str,
        *,
        include_deleted: bool = False,
        **kwargs: Any,
    ) -> list[T]:
        """Query items for list views."""

    @classmethod
    @abstractmethod
    def _build_tree(cls, items: list[T], **kwargs: Any) -> dict[str, Any]:
        """Build a tree structure for list views."""

    @classmethod
    @abstractmethod
    def _search_items(
        cls,
        db: Session,
        user_id: str,
        query: str,
        *,
        limit: int,
        **kwargs: Any,
    ) -> list[T]:
        """Search items for a user."""

    @classmethod
    @abstractmethod
    def _item_to_dict(cls, item: T, **kwargs: Any) -> dict[str, Any]:
        """Convert a model instance to an API payload."""

    @classmethod
    def list_tree(
        cls,
        db: Session,
        user_id: str,
        *,
        include_deleted: bool = False,
        **kwargs: Any,
    ) -> dict[str, list[dict[str, Any]]]:
        """Return a tree payload for the UI."""
        items = cls._query_items(db, user_id, include_deleted=include_deleted, **kwargs)
        tree = cls._build_tree(items, **kwargs)
        return {"children": tree.get("children", [])}

    @classmethod
    def search(
        cls,
        db: Session,
        user_id: str,
        query: str,
        *,
        limit: int = 50,
        **kwargs: Any,
    ) -> dict[str, list[dict[str, Any]]]:
        """Search items and return UI-friendly results."""
        items = cls._search_items(db, user_id, query, limit=limit, **kwargs)
        results = [cls._item_to_dict(item, **kwargs) for item in items]
        return {"items": results}
