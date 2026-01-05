"""User settings API router."""
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, File, UploadFile, Request
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.services.settings_service import SettingsService


router = APIRouter(prefix="/settings", tags=["settings"])


class SettingsResponse(BaseModel):
    """Response payload for user settings."""

    user_id: str
    communication_style: Optional[str] = None
    working_relationship: Optional[str] = None
    name: Optional[str] = None
    job_title: Optional[str] = None
    employer: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    pronouns: Optional[str] = None
    location: Optional[str] = None
    profile_image_url: Optional[str] = None
    enabled_skills: list[str] = []


class SettingsUpdate(BaseModel):
    """Request payload for updating user settings."""

    communication_style: Optional[str] = None
    working_relationship: Optional[str] = None
    name: Optional[str] = None
    job_title: Optional[str] = None
    employer: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    pronouns: Optional[str] = None
    location: Optional[str] = None
    enabled_skills: Optional[list[str]] = None


class ShortcutsPatResponse(BaseModel):
    """Response payload for shortcuts PAT token."""

    token: str


@router.get("", response_model=SettingsResponse)
async def get_settings(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Fetch settings for the current user.

    Args:
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Current settings payload.
    """
    return SettingsResponse(**SettingsService.get_settings(db, user_id))


@router.patch("", response_model=SettingsResponse)
async def update_settings(
    payload: SettingsUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Update settings for the current user.

    Args:
        payload: Settings updates.
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Updated settings payload.
    """
    updates = payload.model_dump(exclude_unset=True)
    return SettingsResponse(**SettingsService.update_settings(db, user_id, updates))


@router.post("/profile-image")
async def upload_profile_image(
    request: Request,
    file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Upload or replace the user's profile image.

    Args:
        request: Incoming request, possibly with raw image body.
        file: Uploaded image file (optional).
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Upload result payload.

    Raises:
        BadRequestError: If content type is not an image.
    """
    contents: bytes
    content_type = ""
    filename = request.headers.get("x-filename") or "profile-image"

    if file is not None:
        content_type = file.content_type or ""
        filename = file.filename or filename
        contents = await file.read()
    else:
        content_type = request.headers.get("content-type") or ""
        if not content_type.startswith("image/"):
            raise BadRequestError("Invalid image type")
        contents = await request.body()

    return SettingsService.upload_profile_image(
        db,
        user_id,
        content_type=content_type,
        contents=contents,
        filename=filename,
    )


@router.get("/profile-image")
async def get_profile_image(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Return the user's profile image content.

    Args:
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Raw image bytes.
    """
    content = SettingsService.get_profile_image(db, user_id)
    return Response(content, media_type="application/octet-stream")


@router.delete("/profile-image")
async def delete_profile_image(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Delete the user's profile image.

    Args:
        db: Database session.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).

    Returns:
        Delete result payload.
    """
    return SettingsService.delete_profile_image(db, user_id)


@router.get("/shortcuts/pat", response_model=ShortcutsPatResponse)
async def get_shortcuts_pat(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Return the current shortcuts PAT token, creating one if missing."""
    token = SettingsService.get_or_create_shortcuts_pat(db, user_id)
    return ShortcutsPatResponse(token=token)


@router.post("/shortcuts/pat/rotate", response_model=ShortcutsPatResponse)
async def rotate_shortcuts_pat(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Rotate the shortcuts PAT token for the current user."""
    token = SettingsService.rotate_shortcuts_pat(db, user_id)
    return ShortcutsPatResponse(token=token)
