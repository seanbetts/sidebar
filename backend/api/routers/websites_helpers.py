"""Helper utilities for website router flows."""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime

from api.config import settings
from api.db.session import SessionLocal, set_session_user_id
from api.models.website import Website
from api.services.jina_service import JinaService
from api.services.web_save_parser import parse_url_local
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


def website_summary(website: Website) -> dict:
    """Build a summary payload for a website record."""
    metadata = website.metadata_ or {}
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
        "archived": metadata.get("archived", False),
        "youtube_transcripts": metadata.get("youtube_transcripts", {}),
        "updated_at": website.updated_at.isoformat() if website.updated_at else None,
        "last_opened_at": website.last_opened_at.isoformat()
        if website.last_opened_at
        else None,
        "deleted_at": website.deleted_at.isoformat() if website.deleted_at else None,
    }
