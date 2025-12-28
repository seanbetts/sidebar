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
from api.services.settings_service import SettingsService


router = APIRouter(prefix="/settings", tags=["settings"])


class SettingsResponse(BaseModel):
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


@router.get("", response_model=SettingsResponse)
async def get_settings(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    return SettingsResponse(**SettingsService.get_settings(db, user_id))


@router.patch("", response_model=SettingsResponse)
async def update_settings(
    payload: SettingsUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    updates = payload.dict(exclude_unset=True)
    return SettingsResponse(**SettingsService.update_settings(db, user_id, updates))


@router.post("/profile-image")
async def upload_profile_image(
    request: Request,
    file: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
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
            raise HTTPException(status_code=400, detail="Invalid image type")
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
    content = SettingsService.get_profile_image(db, user_id)
    return Response(content, media_type="application/octet-stream")


@router.delete("/profile-image")
async def delete_profile_image(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    return SettingsService.delete_profile_image(db, user_id)
