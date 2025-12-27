"""User settings API router."""
from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, Request
from fastapi.responses import Response
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.user_settings_service import UserSettingsService
from api.services.skill_catalog_service import SkillCatalogService
from api.services.storage.service import get_storage_backend
from api.config import settings


router = APIRouter(prefix="/settings", tags=["settings"])
storage_backend = get_storage_backend()


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


DEFAULT_COMMUNICATION_STYLE = """Use UK English.

Be concise and direct.

Always use markdown formatting in your response

Never use em dashes.

Follow explicit user constraints strictly (for example, if asked for two sentences, produce exactly two sentences).

Default to a casual, colleague style.

Use minimal formatting by default. Prefer prose and paragraphs over headings and lists.

Avoid bullet points and numbered lists unless I explicitly ask for a list or the response is genuinely complex.

Do not use emojis unless I use one immediately before."""

DEFAULT_WORKING_RELATIONSHIP = """Challenge my assumptions constructively when useful.

Help with brainstorming questions, simplifying complex topics, and polishing prose.

Critique drafts and use Socratic dialogue to surface blind spots.

Any non obvious claim, statistic, or figure must be backed by an authentic published source. Never fabricate citations. If you cannot source it, say you do not know."""

MAX_STYLE_CHARS = 4000
MAX_PROFILE_FIELD_CHARS = 200


def _resolve_default(value: Optional[str], default: str) -> Optional[str]:
    if value is None:
        return default
    trimmed = value.strip()
    return trimmed if trimmed else default


def _profile_image_url(settings_record) -> Optional[str]:
    if settings_record and settings_record.profile_image_path:
        return "/api/settings/profile-image"
    return None


def _resolve_enabled_skills(settings_record) -> list[str]:
    catalog = SkillCatalogService.list_skills(settings.skills_dir)
    all_ids = [skill["id"] for skill in catalog]
    if not settings_record or settings_record.enabled_skills is None:
        return all_ids
    enabled = [skill_id for skill_id in settings_record.enabled_skills if skill_id in all_ids]
    return enabled


def _clean_text_field(value: Optional[str], field_name: str, max_length: int) -> Optional[str]:
    if value is None:
        return None
    trimmed = value.strip()
    if not trimmed:
        return None
    if len(trimmed) > max_length:
        raise HTTPException(
            status_code=400,
            detail=f"{field_name} exceeds max length ({max_length} characters)",
        )
    return trimmed


@router.get("", response_model=SettingsResponse)
async def get_settings(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    settings = UserSettingsService.get_settings(db, user_id)
    return SettingsResponse(
        user_id=user_id,
        communication_style=_resolve_default(
            settings.communication_style if settings else None,
            DEFAULT_COMMUNICATION_STYLE,
        ),
        working_relationship=_resolve_default(
            settings.working_relationship if settings else None,
            DEFAULT_WORKING_RELATIONSHIP,
        ),
        name=settings.name if settings else None,
        job_title=settings.job_title if settings else None,
        employer=settings.employer if settings else None,
        date_of_birth=settings.date_of_birth if settings else None,
        gender=settings.gender if settings else None,
        pronouns=settings.pronouns if settings else None,
        location=settings.location if settings else None,
        profile_image_url=_profile_image_url(settings),
        enabled_skills=_resolve_enabled_skills(settings),
    )


@router.patch("", response_model=SettingsResponse)
async def update_settings(
    payload: SettingsUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    updates = payload.dict(exclude_unset=True)
    if "communication_style" in updates:
        updates["communication_style"] = _clean_text_field(
            updates.get("communication_style"),
            "communication_style",
            MAX_STYLE_CHARS,
        )
    if "working_relationship" in updates:
        updates["working_relationship"] = _clean_text_field(
            updates.get("working_relationship"),
            "working_relationship",
            MAX_STYLE_CHARS,
        )
    if "name" in updates:
        updates["name"] = _clean_text_field(updates.get("name"), "name", MAX_PROFILE_FIELD_CHARS)
    if "job_title" in updates:
        updates["job_title"] = _clean_text_field(
            updates.get("job_title"),
            "job_title",
            MAX_PROFILE_FIELD_CHARS,
        )
    if "employer" in updates:
        updates["employer"] = _clean_text_field(
            updates.get("employer"),
            "employer",
            MAX_PROFILE_FIELD_CHARS,
        )
    if "gender" in updates:
        updates["gender"] = _clean_text_field(
            updates.get("gender"),
            "gender",
            MAX_PROFILE_FIELD_CHARS,
        )
    if "pronouns" in updates:
        updates["pronouns"] = _clean_text_field(
            updates.get("pronouns"),
            "pronouns",
            MAX_PROFILE_FIELD_CHARS,
        )
    if "location" in updates:
        updates["location"] = _clean_text_field(
            updates.get("location"),
            "location",
            MAX_PROFILE_FIELD_CHARS,
        )
    if "enabled_skills" in updates and updates["enabled_skills"] is not None:
        catalog = SkillCatalogService.list_skills(settings.skills_dir)
        allowed = {skill["id"] for skill in catalog}
        invalid = [skill for skill in updates["enabled_skills"] if skill not in allowed]
        if invalid:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid skills: {', '.join(invalid)}",
            )
    user_settings = UserSettingsService.upsert_settings(
        db,
        user_id,
        **updates,
    )
    return SettingsResponse(
        user_id=user_id,
        communication_style=_resolve_default(
            user_settings.communication_style,
            DEFAULT_COMMUNICATION_STYLE,
        ),
        working_relationship=_resolve_default(
            user_settings.working_relationship,
            DEFAULT_WORKING_RELATIONSHIP,
        ),
        name=user_settings.name,
        job_title=user_settings.job_title,
        employer=user_settings.employer,
        date_of_birth=user_settings.date_of_birth,
        gender=user_settings.gender,
        pronouns=user_settings.pronouns,
        location=user_settings.location,
        profile_image_url=_profile_image_url(user_settings),
        enabled_skills=_resolve_enabled_skills(user_settings),
    )


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

    if not contents:
        raise HTTPException(status_code=400, detail="Empty image payload")

    if not content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Invalid image type")

    if len(contents) > 2 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 2MB)")

    extension = "png"
    if content_type in {"image/jpeg", "image/jpg"}:
        extension = "jpg"
    elif content_type == "image/png":
        extension = "png"
    elif content_type == "image/webp":
        extension = "webp"
    elif content_type == "image/gif":
        extension = "gif"
    elif filename and "." in filename:
        extension = filename.rsplit(".", 1)[-1].lower()

    object_key = f"{user_id}/profile-images/{user_id}.{extension}"
    storage_backend.put_object(object_key, contents, content_type=content_type)

    settings = UserSettingsService.upsert_settings(
        db,
        user_id,
        profile_image_path=object_key,
    )
    return {"profile_image_url": _profile_image_url(settings)}


@router.get("/profile-image")
async def get_profile_image(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    settings = UserSettingsService.get_settings(db, user_id)
    if not settings or not settings.profile_image_path:
        raise HTTPException(status_code=404, detail="Profile image not found")

    try:
        content = storage_backend.get_object(settings.profile_image_path)
    except Exception:
        raise HTTPException(status_code=404, detail="Profile image not found")
    return Response(content, media_type="application/octet-stream")


@router.delete("/profile-image")
async def delete_profile_image(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    settings = UserSettingsService.get_settings(db, user_id)
    if not settings or not settings.profile_image_path:
        raise HTTPException(status_code=404, detail="Profile image not found")

    try:
        storage_backend.delete_object(settings.profile_image_path)
    except Exception:
        raise HTTPException(status_code=500, detail="Failed to delete profile image")

    UserSettingsService.upsert_settings(
        db,
        user_id,
        profile_image_path=None,
    )
    return {"success": True}
