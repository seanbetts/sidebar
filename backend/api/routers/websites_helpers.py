"""Helper utilities for website router flows."""

from __future__ import annotations

from sqlalchemy import inspect
from sqlalchemy.orm.attributes import NO_VALUE

from api.models.website import Website
from api.services.url_normalization_service import extract_youtube_video_id
from api.services.web_save_parser_youtube import fetch_youtube_duration_seconds
from api.services.website_reading_time import (
    extract_reading_time_from_frontmatter,
    normalize_reading_time,
    reading_time_from_duration_seconds,
)


def _resolve_jina_reading_time(
    *,
    metadata: dict[str, str | None],
    source: str,
    fallback_url: str,
) -> str | None:
    """Resolve Jina reading time from metadata or YouTube duration."""
    metadata_reading_time = metadata.get("reading_time")
    if isinstance(metadata_reading_time, str) and metadata_reading_time.strip():
        normalized = normalize_reading_time(metadata_reading_time)
        if normalized:
            return normalized

    for candidate in (source, fallback_url):
        if not candidate or extract_youtube_video_id(candidate) is None:
            continue
        duration_seconds = fetch_youtube_duration_seconds(candidate)
        from_duration = reading_time_from_duration_seconds(duration_seconds)
        if from_duration:
            return from_duration
    return None


def website_summary(website: Website) -> dict:
    """Build a summary payload for a website record."""
    state = inspect(website)
    metadata = website.metadata_ or {}
    reading_time_value: str | None
    loaded_reading_time = state.attrs.reading_time.loaded_value
    if isinstance(loaded_reading_time, str) and loaded_reading_time.strip():
        reading_time_value = normalize_reading_time(loaded_reading_time)
    else:
        metadata_reading_time = metadata.get("reading_time")
        if isinstance(metadata_reading_time, str) and metadata_reading_time.strip():
            reading_time_value = normalize_reading_time(metadata_reading_time)
        else:
            content_value = state.attrs.content.loaded_value
            reading_time_value = (
                extract_reading_time_from_frontmatter(content_value)
                if content_value is not NO_VALUE
                else None
            )
    if reading_time_value == "":
        reading_time_value = None

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
        "youtube_transcripts": metadata.get("youtube_transcripts", {}),
        "reading_time": reading_time_value,
        "created_at": website.created_at.isoformat() if website.created_at else None,
        "updated_at": website.updated_at.isoformat() if website.updated_at else None,
        "last_opened_at": website.last_opened_at.isoformat()
        if website.last_opened_at
        else None,
        "deleted_at": website.deleted_at.isoformat() if website.deleted_at else None,
    }


def website_detail_payload(website: Website) -> dict:
    """Build the canonical detail payload for a website record."""
    return {
        **website_summary(website),
        "content": website.content,
        "source": website.source,
        "url_full": website.url_full,
    }
