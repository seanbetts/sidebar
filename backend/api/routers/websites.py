"""Websites router for archived web content in Postgres."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from api.auth import verify_bearer_token
from api.db.session import get_db
from api.models.website import Website
from api.services.websites_service import WebsitesService, WebsiteNotFoundError

router = APIRouter(prefix="/websites", tags=["websites"])


def website_summary(website: Website) -> dict:
    metadata = website.metadata_ or {}
    return {
        "id": str(website.id),
        "title": website.title,
        "url": website.url,
        "domain": website.domain,
        "saved_at": website.saved_at.isoformat() if website.saved_at else None,
        "published_at": website.published_at.isoformat() if website.published_at else None,
        "pinned": metadata.get("pinned", False),
        "archived": metadata.get("archived", False),
        "updated_at": website.updated_at.isoformat() if website.updated_at else None,
        "last_opened_at": website.last_opened_at.isoformat() if website.last_opened_at else None
    }


@router.get("")
async def list_websites(
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    websites = (
        WebsitesService.list_websites(db)
    )
    return {"items": [website_summary(site) for site in websites]}


@router.get("/{website_id}")
async def get_website(
    website_id: str,
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    website = WebsitesService.get_website(db, website_id, mark_opened=True)
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
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    pinned = bool(request.get("pinned", False))
    try:
        WebsitesService.update_pinned(db, website_id, pinned)
    except WebsiteNotFoundError:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}


@router.patch("/{website_id}/archive")
async def update_archive(
    website_id: str,
    request: dict,
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    archived = bool(request.get("archived", False))
    try:
        WebsitesService.update_archived(db, website_id, archived)
    except WebsiteNotFoundError:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}


@router.delete("/{website_id}")
async def delete_website(
    website_id: str,
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
    deleted = WebsitesService.delete_website(db, website_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}
