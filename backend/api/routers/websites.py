"""Websites router for archived web content in Postgres."""
import uuid
from sqlalchemy import or_
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response
from sqlalchemy.orm import Session
from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.models.website import Website
from api.services.websites_service import WebsitesService, WebsiteNotFoundError

router = APIRouter(prefix="/websites", tags=["websites"])


def parse_website_id(value: str):
    """Parse a website UUID from a string.

    Args:
        value: UUID string.

    Returns:
        Parsed UUID.

    Raises:
        HTTPException: 400 if the value is not a valid UUID.
    """
    try:
        return uuid.UUID(value)
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="Invalid website id")


def website_summary(website: Website) -> dict:
    """Build a summary payload for a website record.

    Args:
        website: Website ORM object.

    Returns:
        Summary dict for list/detail responses.
    """
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
        "last_opened_at": website.last_opened_at.isoformat() if website.last_opened_at else None
    }


@router.get("")
async def list_websites(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """List websites for the current user.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        List of website summaries.
    """
    websites = (
        WebsitesService.list_websites(db, user_id)
    )
    return {"items": [website_summary(site) for site in websites]}


@router.post("/search")
async def search_websites(
    query: str,
    limit: int = 50,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Search websites by title or content.

    Args:
        query: Search query string.
        limit: Max results to return. Defaults to 50.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        List of matching website summaries.

    Raises:
        HTTPException: 400 if query is missing.
    """
    if not query:
        raise HTTPException(status_code=400, detail="query required")

    websites = (
        db.query(Website)
        .filter(
            Website.user_id == user_id,
            Website.deleted_at.is_(None),
            or_(
                Website.title.ilike(f"%{query}%"),
                Website.content.ilike(f"%{query}%"),
            ),
        )
        .order_by(Website.updated_at.desc())
        .limit(limit)
        .all()
    )
    return {"items": [website_summary(site) for site in websites]}


@router.post("/save")
async def save_website(
    request: Request,
    payload: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Save a website using the web-save skill.

    Args:
        request: FastAPI request with executor state.
        payload: Request payload with url.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Skill execution result payload.

    Raises:
        HTTPException: 400 for missing url or skill errors.
    """
    url = payload.get("url", "")
    if not url:
        raise HTTPException(status_code=400, detail="url required")

    executor = request.app.state.executor
    result = await executor.execute("web-save", "save_url.py", [url, "--database", "--user-id", user_id])
    if not result.get("success"):
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to save website"))

    return result


@router.get("/{website_id}")
async def get_website(
    website_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Fetch a website by ID.

    Args:
        website_id: Website ID (UUID string).
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Website detail payload with content.

    Raises:
        HTTPException: 404 if not found.
    """
    website = WebsitesService.get_website(db, user_id, website_id, mark_opened=True)
    if not website:
        raise HTTPException(status_code=404, detail="Website not found")

    return {
        **website_summary(website),
        "content": website.content,
        "source": website.source,
        "url_full": website.url_full
    }


@router.patch("/{website_id}/pin")
async def update_pin(
    website_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Pin or unpin a website.

    Args:
        website_id: Website ID (UUID string).
        request: Request payload with pinned.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        HTTPException: 404 if not found.
    """
    pinned = bool(request.get("pinned", False))
    try:
        website_uuid = parse_website_id(website_id)
        WebsitesService.update_pinned(db, user_id, website_uuid, pinned)
    except WebsiteNotFoundError:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}


@router.patch("/pinned-order")
async def update_pinned_order(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update pinned order for websites.

    Args:
        request: Request payload with order list.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.
    """
    order = request.get("order", [])
    if not isinstance(order, list):
        raise HTTPException(status_code=400, detail="order must be a list")
    website_ids: list[uuid.UUID] = []
    for item in order:
        website_ids.append(parse_website_id(item))

    WebsitesService.update_pinned_order(db, user_id, website_ids)
    return {"success": True}


@router.patch("/{website_id}/rename")
async def update_title(
    website_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Rename a website.

    Args:
        website_id: Website ID (UUID string).
        request: Request payload with title.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        HTTPException: 400 if title is missing, 404 if not found.
    """
    title = request.get("title", "")
    if not title:
        raise HTTPException(status_code=400, detail="title required")
    try:
        website_uuid = parse_website_id(website_id)
        WebsitesService.update_website(db, user_id, website_uuid, title=title)
    except WebsiteNotFoundError:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}


@router.patch("/{website_id}/archive")
async def update_archive(
    website_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Archive or unarchive a website.

    Args:
        website_id: Website ID (UUID string).
        request: Request payload with archived.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        HTTPException: 404 if not found.
    """
    archived = bool(request.get("archived", False))
    try:
        website_uuid = parse_website_id(website_id)
        WebsitesService.update_archived(db, user_id, website_uuid, archived)
    except WebsiteNotFoundError:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}


@router.get("/{website_id}/download")
async def download_website(
    website_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Download a website as a markdown attachment.

    Args:
        website_id: Website ID (UUID string).
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Markdown response with attachment headers.

    Raises:
        HTTPException: 404 if not found.
    """
    website_uuid = parse_website_id(website_id)
    website = WebsitesService.get_website(db, user_id, website_uuid, mark_opened=False)
    if not website:
        raise HTTPException(status_code=404, detail="Website not found")

    filename = f"{website.title}.md"
    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}
    return Response(website.content or "", media_type="text/markdown", headers=headers)


@router.delete("/{website_id}")
async def delete_website(
    website_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    """Delete a website by ID.

    Args:
        website_id: Website ID (UUID string).
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        HTTPException: 404 if not found.
    """
    deleted = WebsitesService.delete_website(db, user_id, website_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}
