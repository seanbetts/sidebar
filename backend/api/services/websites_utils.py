"""Helper utilities for website payloads and conflict detection."""

from __future__ import annotations

from datetime import datetime
from urllib.parse import urlparse

from api.exceptions import ConflictError
from api.models.website import Website
from api.services.website_reading_time import normalize_reading_time


def normalize_url(value: str) -> str:
    """Normalize a URL for storage."""
    parsed = urlparse(value)
    return parsed._replace(query="", fragment="").geturl()


def extract_domain(value: str) -> str:
    """Extract a domain from a URL."""
    parsed = urlparse(value)
    return parsed.netloc or value


def website_sync_payload(website: Website) -> dict[str, object]:
    """Build a sync payload for a website."""
    metadata = website.metadata_ or {}
    reading_time = website.reading_time
    if not reading_time and isinstance(metadata.get("reading_time"), str):
        reading_time = metadata.get("reading_time")
    return {
        "id": str(website.id),
        "title": website.title,
        "url": website.url,
        "domain": website.domain,
        "saved_at": website.saved_at.isoformat() if website.saved_at else None,
        "published_at": website.published_at.isoformat()
        if website.published_at
        else None,
        "pinned": metadata.get("pinned", False),
        "pinned_order": metadata.get("pinned_order"),
        "archived": bool(website.is_archived),
        "favicon_url": metadata.get("favicon_url"),
        "favicon_r2_key": metadata.get("favicon_r2_key"),
        "favicon_extracted_at": metadata.get("favicon_extracted_at"),
        "reading_time": normalize_reading_time(reading_time) if reading_time else None,
        "updated_at": website.updated_at.isoformat() if website.updated_at else None,
        "deleted_at": website.deleted_at.isoformat() if website.deleted_at else None,
    }


def website_conflict_payload(
    website: Website,
    *,
    op: str | None,
    client_updated_at: datetime | None,
    operation_id: str | None = None,
    reason: str | None = None,
) -> dict[str, object]:
    """Build a conflict payload for websites."""
    return {
        "operationId": operation_id,
        "op": op,
        "id": str(website.id),
        "clientUpdatedAt": client_updated_at.isoformat() if client_updated_at else None,
        "serverUpdatedAt": website.updated_at.isoformat()
        if website.updated_at
        else None,
        "serverWebsite": website_sync_payload(website),
        "reason": reason,
    }


def ensure_website_no_conflict(
    website: Website,
    client_updated_at: datetime | None,
    *,
    op: str,
) -> None:
    """Raise ConflictError when website updated after client timestamp."""
    if client_updated_at is None:
        return
    if website.updated_at and website.updated_at > client_updated_at:
        conflict = website_conflict_payload(
            website,
            op=op,
            client_updated_at=client_updated_at,
        )
        raise ConflictError(
            "Website has been updated since last sync", {"conflict": conflict}
        )
