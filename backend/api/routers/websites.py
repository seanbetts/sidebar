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
    try:
        return uuid.UUID(value)
    except (ValueError, TypeError):
        raise HTTPException(status_code=400, detail="Invalid website id")


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
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
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
    pinned = bool(request.get("pinned", False))
    try:
        website_uuid = parse_website_id(website_id)
        WebsitesService.update_pinned(db, user_id, website_uuid, pinned)
    except WebsiteNotFoundError:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}


@router.patch("/{website_id}/rename")
async def update_title(
    website_id: str,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
):
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
    deleted = WebsitesService.delete_website(db, user_id, website_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Website not found")

    return {"success": True}
