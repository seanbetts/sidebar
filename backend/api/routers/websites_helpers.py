"""Helper utilities for website router flows."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime

from sqlalchemy import inspect
from sqlalchemy.orm.attributes import NO_VALUE

from api.config import settings
from api.db.session import SessionLocal, set_session_user_id
from api.models.website import Website
from api.services.favicon_service import FaviconService
from api.services.jina_service import JinaService
from api.services.web_save_parser import extract_favicon_url, parse_url_local
from api.services.website_processing_service import WebsiteProcessingService
from api.services.websites_service import WebsitesService

logger = logging.getLogger(__name__)


def normalize_url(value: str) -> str:
    """Ensure the URL has a scheme."""
    if value.startswith(("http://", "https://")):
        return value
    return f"https://{value}"


def run_quick_save(
    job_id: uuid.UUID, user_id: str, url: str, title: str | None
) -> None:
    """Background task to save a website quickly."""
    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        WebsiteProcessingService.update_job(db, job_id, status="running")
        web_save_mode = settings.web_save_mode.lower().strip()
        logger.info("web-save quick_save start url=%s mode=%s", url, web_save_mode)
        try:
            local_parsed = None
            if web_save_mode in {"local", "compare"}:
                try:
                    local_parsed = parse_url_local(url)
                    logger.info(
                        "web-save local parse ok url=%s title=%s content_len=%s",
                        url,
                        local_parsed.title,
                        len(local_parsed.content),
                    )
                except Exception as exc:
                    logger.info(
                        "web-save local parse failed url=%s error=%s", url, str(exc)
                    )
                    if web_save_mode == "local":
                        local_parsed = None

            if web_save_mode == "local" and local_parsed:
                website = WebsitesService.upsert_website(
                    db,
                    user_id,
                    url=url,
                    title=local_parsed.title,
                    content=local_parsed.content,
                    source=local_parsed.source,
                    url_full=url,
                    saved_at=datetime.now(UTC),
                    published_at=local_parsed.published_at,
                    pinned=False,
                    archived=False,
                )
            else:
                logger.info("web-save using jina url=%s mode=%s", url, web_save_mode)
                markdown = JinaService.fetch_markdown(url)
                metadata, cleaned = JinaService.parse_metadata(markdown)
                resolved_title = (
                    title
                    or metadata.get("title")
                    or JinaService.extract_title(cleaned, url)
                )
                source = metadata.get("url_source") or url
                published_at = JinaService.parse_published_at(
                    metadata.get("published_time")
                )
                website = WebsitesService.upsert_website(
                    db,
                    user_id,
                    url=url,
                    title=resolved_title,
                    content=cleaned,
                    source=source,
                    url_full=url,
                    saved_at=datetime.now(UTC),
                    published_at=published_at,
                    pinned=False,
                    archived=False,
                )
                if web_save_mode == "compare" and local_parsed:
                    logger.info(
                        (
                            "Compare parse for %s: jina_len=%s local_len=%s "
                            "jina_title=%s local_title=%s"
                        ),
                        url,
                        len(cleaned),
                        len(local_parsed.content),
                        resolved_title,
                        local_parsed.title,
                    )
            favicon_url = None
            if local_parsed and local_parsed.favicon_url:
                favicon_url = local_parsed.favicon_url
            if favicon_url is None:
                try:
                    favicon_url = extract_favicon_url(url)
                except Exception:
                    favicon_url = None

            if favicon_url:
                metadata_payload = FaviconService.metadata_payload(
                    favicon_url=favicon_url
                )
                if metadata_payload:
                    try:
                        WebsitesService.update_metadata(
                            db,
                            user_id,
                            website.id,
                            metadata_updates=metadata_payload,
                        )
                    except Exception as exc:
                        logger.warning(
                            "favicon metadata update failed url=%s error=%s",
                            url,
                            str(exc),
                        )

                shared_key = None
                try:
                    shared_key = FaviconService.existing_storage_key(website.domain)
                except Exception as exc:
                    logger.warning(
                        "favicon shared key check failed url=%s error=%s", url, str(exc)
                    )

                if shared_key:
                    try:
                        WebsitesService.update_metadata(
                            db,
                            user_id,
                            website.id,
                            metadata_updates={"favicon_r2_key": shared_key},
                        )
                    except Exception as exc:
                        logger.warning(
                            "favicon shared key update failed url=%s error=%s",
                            url,
                            str(exc),
                        )
                else:
                    try:
                        favicon_key = FaviconService.fetch_and_store_favicon(
                            website.domain,
                            favicon_url,
                        )
                        if favicon_key:
                            WebsitesService.update_metadata(
                                db,
                                user_id,
                                website.id,
                                metadata_updates={"favicon_r2_key": favicon_key},
                            )
                    except Exception as exc:
                        logger.warning(
                            "favicon upload failed url=%s error=%s", url, str(exc)
                        )

            WebsiteProcessingService.update_job(
                db,
                job_id,
                status="completed",
                website_id=website.id,
            )
        except Exception as exc:
            WebsiteProcessingService.update_job(
                db,
                job_id,
                status="failed",
                error_message=str(exc),
            )


def _extract_reading_time(content: str) -> str | None:
    """Extract reading_time from markdown frontmatter and normalize format."""
    if not content or not content.startswith("---"):
        return None
    end = content.find("\n---", 3)
    if end == -1:
        return None
    frontmatter = content[4:end]
    for line in frontmatter.split("\n"):
        if line.startswith("reading_time:"):
            value = line[13:].strip().strip("'\"")
            if not value:
                return None
            return _normalize_reading_time(value)
    return None


def _normalize_reading_time(value: str) -> str:
    """Normalize reading time to consistent format with hours and pluralization."""
    import re

    # Extract number of minutes from formats like "104 min", "5 mins", "1 hr 30 min"
    # First check if already has hours
    hr_match = re.match(r"(\d+)\s*hrs?\s*(?:(\d+)\s*mins?)?", value)
    if hr_match:
        hours = int(hr_match.group(1))
        mins = int(hr_match.group(2)) if hr_match.group(2) else 0
        total_minutes = hours * 60 + mins
    else:
        # Extract just minutes
        min_match = re.match(r"(\d+)\s*mins?", value)
        if min_match:
            total_minutes = int(min_match.group(1))
        else:
            return value  # Can't parse, return as-is

    # Format with proper hours/mins and pluralization
    if total_minutes >= 60:
        hours = total_minutes // 60
        remaining = total_minutes % 60
        hr_label = "hr" if hours == 1 else "hrs"
        if remaining == 0:
            return f"{hours} {hr_label}"
        min_label = "min" if remaining == 1 else "mins"
        return f"{hours} {hr_label} {remaining} {min_label}"
    min_label = "min" if total_minutes == 1 else "mins"
    return f"{total_minutes} {min_label}"


def website_summary(website: Website) -> dict:
    """Build a summary payload for a website record."""
    metadata = website.metadata_ or {}
    reading_time_value: str | None
    reading_time = metadata.get("reading_time")
    if isinstance(reading_time, str) and reading_time.strip():
        reading_time_value = _normalize_reading_time(reading_time.strip())
    else:
        content_value = inspect(website).attrs.content.loaded_value
        reading_time_value = (
            _extract_reading_time(content_value)
            if content_value is not NO_VALUE
            else None
        )

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
