"""Filter dataclasses for list endpoints."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime


@dataclass
class NoteFilters:
    """Filters for listing notes."""

    folder: str | None = None
    pinned: bool | None = None
    archived: bool | None = None
    created_after: datetime | None = None
    created_before: datetime | None = None
    updated_after: datetime | None = None
    updated_before: datetime | None = None
    opened_after: datetime | None = None
    opened_before: datetime | None = None
    title_search: str | None = None


@dataclass
class WebsiteFilters:
    """Filters for listing websites."""

    domain: str | None = None
    pinned: bool | None = None
    archived: bool | None = None
    created_after: datetime | None = None
    created_before: datetime | None = None
    updated_after: datetime | None = None
    updated_before: datetime | None = None
    opened_after: datetime | None = None
    opened_before: datetime | None = None
    published_after: datetime | None = None
    published_before: datetime | None = None
    title_search: str | None = None
