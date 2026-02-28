"""Helper utilities for website router flows."""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any

from sqlalchemy import inspect
from sqlalchemy.orm.attributes import NO_VALUE

from api.db.session import SessionLocal, set_session_user_id
from api.models.website import Website
from api.services.web_save_error_service import (
    classify_web_save_failure,
    classify_web_save_result,
    encode_job_error,
)
from api.services.website_processing_service import WebsiteProcessingService
from api.services.website_reading_time import (
    extract_reading_time_from_frontmatter,
    normalize_reading_time,
)

logger = logging.getLogger(__name__)


def normalize_url(value: str) -> str:
    """Ensure the URL has a scheme."""
    if value.startswith(("http://", "https://")):
        return value
    return f"https://{value}"


def run_quick_save(
    job_id: uuid.UUID,
    user_id: str,
    url: str,
    title: str | None,
    executor: Any,
) -> None:
    """Background task to save a website using the canonical web-save skill path."""
    if title:
        logger.info(
            "web-save quick-save title override ignored; canonical "
            "skill pipeline does not accept title"
        )
    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        WebsiteProcessingService.update_job(db, job_id, status="running")
        try:
            result = asyncio.run(
                executor.execute(
                    "web-save",
                    "save_url.py",
                    [url, "--database", "--user-id", user_id],
                    user_id=user_id,
                )
            )
            if not result.get("success"):
                classified = classify_web_save_result(
                    result,
                    url=url,
                    target_url=url,
                )
                WebsiteProcessingService.update_job(
                    db,
                    job_id,
                    status="failed",
                    error_message=encode_job_error(classified),
                )
                return

            data = result.get("data") if isinstance(result.get("data"), dict) else {}
            website_id_raw = data.get("id")
            website_id: uuid.UUID | None = None
            if isinstance(website_id_raw, str):
                try:
                    website_id = uuid.UUID(website_id_raw)
                except ValueError:
                    website_id = None
            WebsiteProcessingService.update_job(
                db,
                job_id,
                status="completed",
                website_id=website_id,
            )
        except Exception as exc:
            WebsiteProcessingService.update_job(
                db,
                job_id,
                status="failed",
                error_message=encode_job_error(
                    classify_web_save_failure(
                        upstream_error_type=type(exc).__name__,
                        upstream_message=str(exc),
                        url=url,
                        target_url=url,
                    )
                ),
            )


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
        "updated_at": website.updated_at.isoformat() if website.updated_at else None,
        "last_opened_at": website.last_opened_at.isoformat()
        if website.last_opened_at
        else None,
        "deleted_at": website.deleted_at.isoformat() if website.deleted_at else None,
    }
