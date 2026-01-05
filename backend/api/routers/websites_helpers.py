"""Helper utilities for website router flows."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from api.db.session import SessionLocal, set_session_user_id
from api.models.website import Website
from api.services.jina_service import JinaService
from api.services.website_processing_service import WebsiteProcessingService
from api.services.websites_service import WebsitesService


def normalize_url(value: str) -> str:
    """Ensure the URL has a scheme."""
    if value.startswith(("http://", "https://")):
        return value
    return f"https://{value}"


def run_quick_save(job_id: uuid.UUID, user_id: str, url: str, title: str | None) -> None:
    """Background task to save a website quickly."""
    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        WebsiteProcessingService.update_job(db, job_id, status="running")
        try:
            markdown = JinaService.fetch_markdown(url)
            metadata, cleaned = JinaService.parse_metadata(markdown)
            resolved_title = title or metadata.get("title") or JinaService.extract_title(cleaned, url)
            source = metadata.get("url_source") or url
            published_at = JinaService.parse_published_at(metadata.get("published_time"))

            website = WebsitesService.upsert_website(
                db,
                user_id,
                url=url,
                title=resolved_title,
                content=cleaned,
                source=source,
                url_full=url,
                saved_at=datetime.now(timezone.utc),
                published_at=published_at,
                pinned=False,
                archived=False,
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
        "published_at": website.published_at.isoformat() if website.published_at else None,
        "pinned": metadata.get("pinned", False),
        "pinned_order": metadata.get("pinned_order"),
        "archived": metadata.get("archived", False),
        "updated_at": website.updated_at.isoformat() if website.updated_at else None,
        "last_opened_at": website.last_opened_at.isoformat() if website.last_opened_at else None,
    }
