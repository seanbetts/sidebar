"""Websites router for archived web content in Postgres."""

import logging
import uuid

from fastapi import APIRouter, BackgroundTasks, Depends, Request
from fastapi.responses import JSONResponse, Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError, NotFoundError, WebsiteNotFoundError
from api.routers.websites_helpers import normalize_url, run_quick_save, website_summary
from api.schemas.filters import WebsiteFilters
from api.services.website_processing_service import WebsiteProcessingService
from api.services.website_transcript_service import WebsiteTranscriptService
from api.services.websites_service import WebsitesService
from api.utils.validation import parse_uuid

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/websites", tags=["websites"])


@router.get("")
async def list_websites(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """List websites for the current user.

    Args:
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        List of website summaries.
    """
    websites = WebsitesService.list_websites(db, user_id, WebsiteFilters())
    return {"items": [website_summary(site) for site in websites]}


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
        raise BadRequestError("order must be a list")
    website_ids: list[uuid.UUID] = []
    for item in order:
        website_ids.append(parse_uuid(item, "website", "id"))

    WebsitesService.update_pinned_order(db, user_id, website_ids)
    return {"success": True}


@router.post("/search")
async def search_websites(
    query: str,
    limit: int = 50,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
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
        BadRequestError: If query is missing.
    """
    if not query:
        raise BadRequestError("query required")

    websites = WebsitesService.search_websites(db, user_id, query, limit=limit)
    return {"items": [website_summary(site) for site in websites]}


@router.post("/quick-save")
async def quick_save_website(
    request: dict,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Save a website with lightweight Jina fetch in the background."""
    url = str(request.get("url", "")).strip()
    if not url:
        raise BadRequestError("url required")
    title = request.get("title")
    normalized_url = normalize_url(url)

    job = WebsiteProcessingService.create_job(db, user_id, normalized_url)
    background_tasks.add_task(run_quick_save, job.id, user_id, normalized_url, title)
    return JSONResponse(
        status_code=202, content={"success": True, "data": {"job_id": str(job.id)}}
    )


@router.get("/quick-save/{job_id}")
async def get_quick_save_job(
    job_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return quick-save job status."""
    job = WebsiteProcessingService.get_job(db, user_id, job_id)
    if not job:
        raise NotFoundError("Website job", str(job_id))

    return {
        "id": str(job.id),
        "status": job.status,
        "error_message": job.error_message,
        "website_id": str(job.website_id) if job.website_id else None,
        "created_at": job.created_at.isoformat() if job.created_at else None,
        "updated_at": job.updated_at.isoformat() if job.updated_at else None,
    }


@router.post("/save")
async def save_website(
    request: Request,
    payload: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
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
        BadRequestError: For missing url or skill errors.
    """
    url = payload.get("url", "")
    if not url:
        raise BadRequestError("url required")

    executor = request.app.state.executor
    result = await executor.execute(
        "web-save", "save_url.py", [url, "--database", "--user-id", user_id]
    )
    if not result.get("success"):
        logger.error(
            "websites save failed url=%s error=%s",
            url,
            result.get("error"),
        )
        raise BadRequestError("Unable to save website")

    return result


@router.post("/{website_id}/youtube-transcript")
async def append_youtube_transcript(
    website_id: uuid.UUID,
    payload: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Queue a YouTube transcript job for a website."""
    youtube_url = str(payload.get("url", "")).strip()
    if not youtube_url:
        raise BadRequestError("url required")

    try:
        result = WebsiteTranscriptService.enqueue_youtube_transcript(
            db,
            user_id,
            website_id,
            youtube_url,
        )
    except ValueError as exc:
        raise BadRequestError(str(exc)) from exc

    if result.status == "ready":
        website = WebsitesService.get_website(
            db, user_id, website_id, mark_opened=False
        )
        if not website:
            raise NotFoundError("Website", str(website_id))

        return {
            **website_summary(website),
            "content": result.content,
            "source": website.source,
            "url_full": website.url_full,
        }

    return JSONResponse(
        status_code=202,
        content={
            "success": True,
            "data": {
                "status": result.status,
                "file_id": str(result.file_id) if result.file_id else None,
            },
        },
    )


@router.get("/{website_id}")
async def get_website(
    website_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch a website by ID.

    Args:
        website_id: Website UUID.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Website detail payload with content.

    Raises:
        NotFoundError: If not found.
    """
    website = WebsitesService.get_website(db, user_id, website_id, mark_opened=True)
    if not website:
        raise NotFoundError("Website", str(website_id))

    WebsiteTranscriptService.sync_transcripts_for_website(
        db,
        user_id=user_id,
        website_id=website_id,
    )

    return {
        **website_summary(website),
        "content": website.content,
        "source": website.source,
        "url_full": website.url_full,
    }


@router.patch("/{website_id}/pin")
async def update_pin(
    website_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Pin or unpin a website.

    Args:
        website_id: Website UUID.
        request: Request payload with pinned.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        NotFoundError: If not found.
    """
    pinned = bool(request.get("pinned", False))
    try:
        website = WebsitesService.update_pinned(db, user_id, website_id, pinned)
    except WebsiteNotFoundError as exc:
        raise NotFoundError("Website", str(website_id)) from exc

    return website_summary(website)


@router.patch("/{website_id}/rename")
async def update_title(
    website_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Rename a website.

    Args:
        website_id: Website UUID.
        request: Request payload with title.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        BadRequestError: If title is missing.
        NotFoundError: If not found.
    """
    title = request.get("title", "")
    if not title:
        raise BadRequestError("title required")
    try:
        website = WebsitesService.update_website(db, user_id, website_id, title=title)
    except WebsiteNotFoundError as exc:
        raise NotFoundError("Website", str(website_id)) from exc

    return website_summary(website)


@router.patch("/{website_id}/archive")
async def update_archive(
    website_id: uuid.UUID,
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Archive or unarchive a website.

    Args:
        website_id: Website UUID.
        request: Request payload with archived.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        NotFoundError: If not found.
    """
    archived = bool(request.get("archived", False))
    try:
        website = WebsitesService.update_archived(db, user_id, website_id, archived)
    except WebsiteNotFoundError as exc:
        raise NotFoundError("Website", str(website_id)) from exc

    return website_summary(website)


@router.get("/{website_id}/download")
async def download_website(
    website_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Download a website as a markdown attachment.

    Args:
        website_id: Website UUID.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Markdown response with attachment headers.

    Raises:
        NotFoundError: If not found.
    """
    website = WebsitesService.get_website(db, user_id, website_id, mark_opened=False)
    if not website:
        raise NotFoundError("Website", str(website_id))

    filename = f"{website.title}.md"
    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}
    return Response(website.content or "", media_type="text/markdown", headers=headers)


@router.delete("/{website_id}")
async def delete_website(
    website_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Delete a website by ID.

    Args:
        website_id: Website UUID.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Success flag.

    Raises:
        NotFoundError: If not found.
    """
    website = WebsitesService.get_website(db, user_id, website_id, mark_opened=False)
    if not website:
        raise NotFoundError("Website", str(website_id))
    deleted = WebsitesService.delete_website(db, user_id, website_id)
    if not deleted:
        raise NotFoundError("Website", str(website_id))

    return website_summary(website)
