"""Websites router for archived web content in Postgres."""
# ruff: noqa: B008

import logging
import uuid
from urllib.parse import urlparse

from fastapi import APIRouter, Body, Depends
from fastapi.responses import JSONResponse, Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError, NotFoundError, WebsiteNotFoundError
from api.middleware import rate_limit as rate_limit_module
from api.routers.download_headers import markdown_download_headers
from api.routers.websites_helpers import website_detail_payload, website_summary
from api.schemas.filters import WebsiteFilters
from api.services.website_processing_service import WebsiteProcessingService
from api.services.website_transcript_service import WebsiteTranscriptService
from api.services.websites_service import WebsitesService
from api.services.websites_sync_service import WebsitesSyncService
from api.services.websites_utils import website_sync_payload
from api.utils.timestamps import parse_client_timestamp
from api.utils.validation import parse_uuid

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/websites", tags=["websites"])
ARCHIVED_LIST_MAX_LIMIT = 500


def _validate_save_website_url(url: str) -> None:
    """Reject save inputs that this flow does not support."""
    candidate = url.strip()
    if not candidate:
        raise BadRequestError("url required")

    parsed = urlparse(
        candidate
        if candidate.startswith(("http://", "https://"))
        else f"https://{candidate}"
    )
    try:
        port = parsed.port
    except ValueError as exc:
        raise BadRequestError("Invalid URL", details={"reason": "invalid_url"}) from exc

    if port is not None:
        raise BadRequestError("Invalid URL", details={"reason": "invalid_url"})


@router.get("")
def list_websites(
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
    websites = WebsitesService.list_websites(
        db,
        user_id,
        WebsiteFilters(archived=False),
    )
    summary = WebsitesService.archived_summary(db, user_id)
    return {
        "items": [website_summary(site) for site in websites],
        **summary,
    }


@router.get("/archived")
def list_archived_websites(
    limit: int = 200,
    offset: int = 0,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """List archived websites for the current user."""
    limit = max(1, min(limit, ARCHIVED_LIST_MAX_LIMIT))
    offset = max(0, offset)
    websites = WebsitesService.list_websites(
        db,
        user_id,
        WebsiteFilters(archived=True),
        limit=limit,
        offset=offset,
    )
    return {"items": [website_summary(site) for site in websites]}


@router.patch("/pinned-order")
def update_pinned_order(
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
def search_websites(
    query: str,
    limit: int = 50,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    _rate_limit: None = Depends(rate_limit_module.website_search_rate_limit),
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


@router.post("/save")
async def save_website(
    payload: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    _rate_limit: None = Depends(rate_limit_module.website_save_rate_limit),
    db: Session = Depends(get_db),
):
    """Queue an async website save job.

    Args:
        payload: Request payload with url.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        202 with job_id and status.

    Raises:
        BadRequestError: For missing or invalid url.
    """
    url = str(payload.get("url", "")).strip()
    _validate_save_website_url(url)

    job = WebsiteProcessingService.create_job(db, user_id, url)
    return JSONResponse(
        status_code=202,
        content={"job_id": str(job.id), "status": "queued"},
    )


@router.post("/{website_id}/youtube-transcript")
def append_youtube_transcript(
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
            **website_detail_payload(website),
            "content": result.content,
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


@router.get("/jobs/{job_id}")
def get_job_status(
    job_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Get the status of an async website save job.

    Args:
        job_id: Job UUID.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Job status with website payload on completion,
        or error details on failure.

    Raises:
        NotFoundError: If job does not exist for this user.
    """
    job = WebsiteProcessingService.get_job(db, user_id, job_id)
    if not job:
        raise NotFoundError("Job", str(job_id))

    client_status, client_error = WebsiteProcessingService.status_for_client(job)
    result: dict = {"job_id": str(job.id), "status": client_status}

    if client_status == "completed" and job.website_id:
        website = WebsitesService.get_website(
            db, user_id, job.website_id, mark_opened=False
        )
        if website:
            result["website"] = website_detail_payload(website)

    if client_status in {"failed", "stalled"} and client_error:
        result["error"] = {"message": client_error}

    return result


@router.post("/jobs/{job_id}/cancel")
def cancel_job(
    job_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Cancel an async website save job."""
    job = WebsiteProcessingService.cancel_job(db, user_id, job_id)
    if not job:
        raise NotFoundError("Job", str(job_id))
    return {"job_id": str(job.id), "status": job.status}


@router.get("/{website_id}")
def get_website(
    website_id: uuid.UUID,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch a website by ID.

    Args:
        website_id: Website UUID.
        request: Optional payload with client_updated_at.
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

    return website_detail_payload(website)


@router.patch("/{website_id}/pin")
def update_pin(
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
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    try:
        website = WebsitesService.update_pinned(
            db,
            user_id,
            website_id,
            pinned,
            client_updated_at=client_updated_at,
        )
    except WebsiteNotFoundError as exc:
        raise NotFoundError("Website", str(website_id)) from exc

    return website_summary(website)


@router.patch("/{website_id}/rename")
def update_title(
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
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    if not title:
        raise BadRequestError("title required")
    try:
        website = WebsitesService.update_website(
            db,
            user_id,
            website_id,
            title=title,
            client_updated_at=client_updated_at,
        )
    except WebsiteNotFoundError as exc:
        raise NotFoundError("Website", str(website_id)) from exc

    return website_summary(website)


@router.patch("/{website_id}/archive")
def update_archive(
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
    client_updated_at = parse_client_timestamp(
        request.get("client_updated_at") or request.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    try:
        website = WebsitesService.update_archived(
            db,
            user_id,
            website_id,
            archived,
            client_updated_at=client_updated_at,
        )
    except WebsiteNotFoundError as exc:
        raise NotFoundError("Website", str(website_id)) from exc

    return website_summary(website)


@router.get("/{website_id}/download")
def download_website(
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
    headers = markdown_download_headers(filename)
    return Response(website.content or "", media_type="text/markdown", headers=headers)


@router.delete("/{website_id}")
def delete_website(
    website_id: uuid.UUID,
    request: dict | None = Body(default=None),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Delete a website by ID.

    Args:
        website_id: Website UUID.
        request: Optional payload with client_updated_at.
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
    payload = request or {}
    client_updated_at = parse_client_timestamp(
        payload.get("client_updated_at") or payload.get("clientUpdatedAt"),
        field_name="client_updated_at",
    )
    deleted = WebsitesService.delete_website(
        db,
        user_id,
        website_id,
        client_updated_at=client_updated_at,
    )
    if not deleted:
        raise NotFoundError("Website", str(website_id))

    return website_summary(website)


@router.post("/sync")
def sync_websites(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Apply offline website operations and return updates since last sync."""
    result = WebsitesSyncService.sync_operations(db, user_id, request)
    return {
        "applied": result.applied_ids,
        "websites": [website_summary(site) for site in result.websites],
        "conflicts": result.conflicts,
        "updates": {
            "items": [website_sync_payload(site) for site in result.updated_websites],
        },
        "serverUpdatedSince": result.server_updated_since.isoformat()
        if result.server_updated_since
        else None,
    }
