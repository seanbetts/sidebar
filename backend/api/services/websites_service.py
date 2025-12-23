"""Websites service for shared website business logic."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Iterable, Optional
from urllib.parse import urlparse

from sqlalchemy.orm import Session

from api.models.website import Website


class WebsiteNotFoundError(Exception):
    """Raised when a website is not found."""


class WebsitesService:
    """Service layer for websites operations."""

    @staticmethod
    def normalize_url(value: str) -> str:
        parsed = urlparse(value)
        normalized = parsed._replace(query="", fragment="").geturl()
        return normalized

    @staticmethod
    def extract_domain(value: str) -> str:
        parsed = urlparse(value)
        return parsed.netloc or value

    @staticmethod
    def save_website(
        db: Session,
        *,
        url: str,
        title: str,
        content: str,
        source: Optional[str] = None,
        url_full: Optional[str] = None,
        saved_at: Optional[datetime] = None,
        published_at: Optional[datetime] = None,
        pinned: bool = False,
        archived: bool = False,
    ) -> Website:
        now = datetime.now(timezone.utc)
        normalized_url = WebsitesService.normalize_url(url)
        domain = WebsitesService.extract_domain(normalized_url)
        metadata = {"pinned": pinned, "archived": archived}

        website = Website(
            url=normalized_url,
            url_full=url_full,
            domain=domain,
            title=title,
            content=content,
            source=source,
            saved_at=saved_at,
            published_at=published_at,
            metadata_=metadata,
            created_at=now,
            updated_at=now,
            last_opened_at=None,
            deleted_at=None,
        )
        db.add(website)
        db.commit()
        db.refresh(website)
        return website

    @staticmethod
    def update_website(
        db: Session,
        website_id: uuid.UUID,
        *,
        title: Optional[str] = None,
        content: Optional[str] = None,
        source: Optional[str] = None,
        saved_at: Optional[datetime] = None,
        published_at: Optional[datetime] = None,
    ) -> Website:
        website = (
            db.query(Website)
            .filter(Website.id == website_id, Website.deleted_at.is_(None))
            .first()
        )
        if not website:
            raise WebsiteNotFoundError(f"Website not found: {website_id}")

        if title is not None:
            website.title = title
        if content is not None:
            website.content = content
        if source is not None:
            website.source = source
        if saved_at is not None:
            website.saved_at = saved_at
        if published_at is not None:
            website.published_at = published_at

        website.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(website)
        return website

    @staticmethod
    def update_pinned(
        db: Session,
        website_id: uuid.UUID,
        pinned: bool,
    ) -> Website:
        website = (
            db.query(Website)
            .filter(Website.id == website_id, Website.deleted_at.is_(None))
            .first()
        )
        if not website:
            raise WebsiteNotFoundError(f"Website not found: {website_id}")

        website.metadata_ = {**(website.metadata_ or {}), "pinned": pinned}
        website.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(website)
        return website

    @staticmethod
    def update_archived(
        db: Session,
        website_id: uuid.UUID,
        archived: bool,
    ) -> Website:
        website = (
            db.query(Website)
            .filter(Website.id == website_id, Website.deleted_at.is_(None))
            .first()
        )
        if not website:
            raise WebsiteNotFoundError(f"Website not found: {website_id}")

        website.metadata_ = {**(website.metadata_ or {}), "archived": archived}
        website.updated_at = datetime.now(timezone.utc)
        db.commit()
        db.refresh(website)
        return website

    @staticmethod
    def delete_website(db: Session, website_id: uuid.UUID) -> bool:
        website = (
            db.query(Website)
            .filter(Website.id == website_id, Website.deleted_at.is_(None))
            .first()
        )
        if not website:
            return False

        now = datetime.now(timezone.utc)
        website.deleted_at = now
        website.updated_at = now
        db.commit()
        return True

    @staticmethod
    def get_website(
        db: Session,
        website_id: uuid.UUID,
        *,
        mark_opened: bool = True,
    ) -> Optional[Website]:
        website = (
            db.query(Website)
            .filter(Website.id == website_id, Website.deleted_at.is_(None))
            .first()
        )
        if not website:
            return None

        if mark_opened:
            website.last_opened_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(website)
        return website

    @staticmethod
    def list_websites(db: Session) -> Iterable[Website]:
        return (
            db.query(Website)
            .filter(Website.deleted_at.is_(None))
            .order_by(Website.saved_at.desc().nullslast(), Website.created_at.desc())
            .all()
        )
