"""Websites service for shared website business logic."""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Iterable, Optional
from urllib.parse import urlparse

from sqlalchemy.orm import Session, load_only

from api.models.website import Website


class WebsiteNotFoundError(Exception):
    """Raised when a website is not found."""


class WebsitesService:
    """Service layer for websites operations."""

    @staticmethod
    def normalize_url(value: str) -> str:
        """Normalize a URL for storage.

        Args:
            value: Raw URL string.

        Returns:
            Normalized URL without query or fragment.
        """
        parsed = urlparse(value)
        normalized = parsed._replace(query="", fragment="").geturl()
        return normalized

    @staticmethod
    def extract_domain(value: str) -> str:
        """Extract a domain from a URL.

        Args:
            value: URL string.

        Returns:
            Domain host portion or original value.
        """
        parsed = urlparse(value)
        return parsed.netloc or value

    @staticmethod
    def get_by_url(
        db: Session,
        user_id: str,
        url: str,
        *,
        include_deleted: bool = False
    ) -> Optional[Website]:
        """Fetch a website by normalized URL.

        Args:
            db: Database session.
            user_id: Current user ID.
            url: URL string to normalize and match.
            include_deleted: Include soft-deleted records when True.

        Returns:
            Matching Website or None.
        """
        normalized_url = WebsitesService.normalize_url(url)
        query = db.query(Website).filter(
            Website.user_id == user_id,
            Website.url == normalized_url,
        )
        if not include_deleted:
            query = query.filter(Website.deleted_at.is_(None))
        return query.first()

    @staticmethod
    def save_website(
        db: Session,
        user_id: str,
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
        """Create a website record.

        Args:
            db: Database session.
            user_id: Current user ID.
            url: Normalized or raw URL.
            title: Website title.
            content: Stored content.
            source: Optional source label.
            url_full: Optional full URL.
            saved_at: Optional saved timestamp.
            published_at: Optional published timestamp.
            pinned: Initial pinned state. Defaults to False.
            archived: Initial archived state. Defaults to False.

        Returns:
            Newly created Website.
        """
        now = datetime.now(timezone.utc)
        normalized_url = WebsitesService.normalize_url(url)
        domain = WebsitesService.extract_domain(normalized_url)
        metadata = {"pinned": pinned, "archived": archived}

        website = Website(
            user_id=user_id,
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
    def upsert_website(
        db: Session,
        user_id: str,
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
        """Create or update a website record by URL.

        Args:
            db: Database session.
            user_id: Current user ID.
            url: URL string to normalize and upsert.
            title: Website title.
            content: Stored content.
            source: Optional source label.
            url_full: Optional full URL.
            saved_at: Optional saved timestamp.
            published_at: Optional published timestamp.
            pinned: Initial pinned state if new.
            archived: Initial archived state if new.

        Returns:
            Upserted Website.
        """
        now = datetime.now(timezone.utc)
        normalized_url = WebsitesService.normalize_url(url)
        domain = WebsitesService.extract_domain(normalized_url)

        website = WebsitesService.get_by_url(db, user_id, normalized_url, include_deleted=True)
        if website:
            website.url_full = url_full or website.url_full
            website.domain = domain
            website.title = title
            website.content = content
            website.source = source
            website.saved_at = saved_at
            website.published_at = published_at
            metadata = {**(website.metadata_ or {}), "archived": False}
            if "pinned" not in metadata:
                metadata["pinned"] = pinned
            website.metadata_ = metadata
            if website.deleted_at is not None:
                website.deleted_at = None
            website.updated_at = now
            db.commit()
            db.refresh(website)
            return website

        metadata = {"pinned": pinned, "archived": archived}
        website = Website(
            user_id=user_id,
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
        user_id: str,
        website_id: uuid.UUID,
        *,
        title: Optional[str] = None,
        content: Optional[str] = None,
        source: Optional[str] = None,
        saved_at: Optional[datetime] = None,
        published_at: Optional[datetime] = None,
    ) -> Website:
        """Update a website record by ID.

        Args:
            db: Database session.
            user_id: Current user ID.
            website_id: Website UUID.
            title: Optional new title.
            content: Optional new content.
            source: Optional new source label.
            saved_at: Optional new saved timestamp.
            published_at: Optional new published timestamp.

        Returns:
            Updated Website.

        Raises:
            WebsiteNotFoundError: If no matching website exists.
        """
        website = (
            db.query(Website)
            .filter(
                Website.user_id == user_id,
                Website.id == website_id,
                Website.deleted_at.is_(None),
            )
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
        user_id: str,
        website_id: uuid.UUID,
        pinned: bool,
    ) -> Website:
        """Update pinned status for a website.

        Args:
            db: Database session.
            user_id: Current user ID.
            website_id: Website UUID.
            pinned: Desired pinned state.

        Returns:
            Updated Website.

        Raises:
            WebsiteNotFoundError: If no matching website exists.
        """
        website = (
            db.query(Website)
            .filter(
                Website.user_id == user_id,
                Website.id == website_id,
                Website.deleted_at.is_(None),
            )
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
        user_id: str,
        website_id: uuid.UUID,
        archived: bool,
    ) -> Website:
        """Update archived status for a website.

        Args:
            db: Database session.
            user_id: Current user ID.
            website_id: Website UUID.
            archived: Desired archived state.

        Returns:
            Updated Website.

        Raises:
            WebsiteNotFoundError: If no matching website exists.
        """
        website = (
            db.query(Website)
            .filter(
                Website.user_id == user_id,
                Website.id == website_id,
                Website.deleted_at.is_(None),
            )
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
    def delete_website(db: Session, user_id: str, website_id: uuid.UUID) -> bool:
        """Soft delete a website by setting deleted_at.

        Args:
            db: Database session.
            user_id: Current user ID.
            website_id: Website UUID.

        Returns:
            True if deleted, False if not found.
        """
        website = (
            db.query(Website)
            .filter(
                Website.user_id == user_id,
                Website.id == website_id,
                Website.deleted_at.is_(None),
            )
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
        user_id: str,
        website_id: uuid.UUID,
        *,
        mark_opened: bool = True,
    ) -> Optional[Website]:
        """Fetch a website by ID.

        Args:
            db: Database session.
            user_id: Current user ID.
            website_id: Website UUID.
            mark_opened: Whether to update last_opened_at. Defaults to True.

        Returns:
            Website if found, otherwise None.
        """
        website = (
            db.query(Website)
            .filter(
                Website.user_id == user_id,
                Website.id == website_id,
                Website.deleted_at.is_(None),
            )
            .first()
        )
        if not website:
            return None

        if mark_opened:
            website.last_opened_at = datetime.now(timezone.utc)
            db.commit()
        return website

    @staticmethod
    def list_websites(
        db: Session,
        user_id: str,
        *,
        domain: Optional[str] = None,
        pinned: Optional[bool] = None,
        archived: Optional[bool] = None,
        created_after: Optional[datetime] = None,
        created_before: Optional[datetime] = None,
        updated_after: Optional[datetime] = None,
        updated_before: Optional[datetime] = None,
        opened_after: Optional[datetime] = None,
        opened_before: Optional[datetime] = None,
        published_after: Optional[datetime] = None,
        published_before: Optional[datetime] = None,
        title_search: Optional[str] = None,
    ) -> Iterable[Website]:
        """List websites using optional filters.

        Args:
            db: Database session.
            user_id: Current user ID.
            domain: Optional domain filter.
            pinned: Optional pinned filter.
            archived: Optional archived filter.
            created_after: Optional created_at lower bound.
            created_before: Optional created_at upper bound.
            updated_after: Optional updated_at lower bound.
            updated_before: Optional updated_at upper bound.
            opened_after: Optional last_opened_at lower bound.
            opened_before: Optional last_opened_at upper bound.
            published_after: Optional published_at lower bound.
            published_before: Optional published_at upper bound.
            title_search: Optional title substring search.

        Returns:
            List of matching websites ordered by saved_at/created_at.
        """
        query = db.query(Website).options(load_only(
            Website.id,
            Website.title,
            Website.url,
            Website.domain,
            Website.saved_at,
            Website.published_at,
            Website.metadata_,
            Website.updated_at,
            Website.last_opened_at,
        )).filter(
            Website.user_id == user_id,
            Website.deleted_at.is_(None),
        )

        if domain is not None:
            query = query.filter(Website.domain == domain)

        if pinned is not None:
            query = query.filter(Website.metadata_["pinned"].astext == str(pinned).lower())

        if archived is not None:
            query = query.filter(Website.metadata_["archived"].astext == str(archived).lower())

        if created_after is not None:
            query = query.filter(Website.created_at >= created_after)
        if created_before is not None:
            query = query.filter(Website.created_at <= created_before)
        if updated_after is not None:
            query = query.filter(Website.updated_at >= updated_after)
        if updated_before is not None:
            query = query.filter(Website.updated_at <= updated_before)
        if opened_after is not None:
            query = query.filter(Website.last_opened_at >= opened_after)
        if opened_before is not None:
            query = query.filter(Website.last_opened_at <= opened_before)
        if published_after is not None:
            query = query.filter(Website.published_at >= published_after)
        if published_before is not None:
            query = query.filter(Website.published_at <= published_before)

        if title_search:
            query = query.filter(Website.title.ilike(f"%{title_search}%"))

        return (
            query.order_by(Website.saved_at.desc().nullslast(), Website.created_at.desc())
            .all()
        )
