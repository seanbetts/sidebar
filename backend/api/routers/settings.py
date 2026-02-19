"""User settings API router."""
# ruff: noqa: B008

from datetime import date

from fastapi import APIRouter, Depends, File, Request, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.services.settings_service import SettingsService
from api.services.user_ai_provider_settings_service import (
    UserAIProviderSettingsService,
)

router = APIRouter(prefix="/settings", tags=["settings"])


class AssistantIdentityPayload(BaseModel):
    """Assistant identity payload for tone, values, and boundaries."""

    name: str | None = None
    tone: str | None = None
    boundaries: str | None = None
    values: str | None = None


class AssistantSoulPayload(BaseModel):
    """Assistant soul payload for durable operating guidance."""

    purpose: str | None = None
    operating_principles: str | None = None
    adaptation_policy: str | None = None
    success_signals: str | None = None


class AgentFieldMetaPayload(BaseModel):
    """Metadata for assistant-managed field updates."""

    updated_at: str
    version: int
    reason: str | None = None


class SettingsResponse(BaseModel):
    """Response payload for user settings."""

    user_id: str
    communication_style: str | None = None
    working_relationship: str | None = None
    name: str | None = None
    job_title: str | None = None
    employer: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
    pronouns: str | None = None
    location: str | None = None
    profile_image_url: str | None = None
    enabled_skills: list[str] = []
    assistant_identity: AssistantIdentityPayload | None = None
    assistant_identity_meta: AgentFieldMetaPayload | None = None
    assistant_soul: AssistantSoulPayload | None = None
    assistant_soul_meta: AgentFieldMetaPayload | None = None
    ai_primary_provider: str | None = None
    ai_fallback_to_managed: bool = False
    ai_primary_provider_has_key: bool = False
    ai_primary_provider_key_last4: str | None = None


class SettingsUpdate(BaseModel):
    """Request payload for updating user settings."""

    model_config = ConfigDict(extra="forbid")

    communication_style: str | None = None
    working_relationship: str | None = None
    name: str | None = None
    job_title: str | None = None
    employer: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
    pronouns: str | None = None
    location: str | None = None
    enabled_skills: list[str] | None = None
    ai_primary_provider: str | None = None
    ai_fallback_to_managed: bool | None = None


class ShortcutsPatResponse(BaseModel):
    """Response payload for shortcuts PAT token."""

    token: str


class ProviderKeyUpdate(BaseModel):
    """Request payload for creating or updating a provider API key."""

    model_config = ConfigDict(extra="forbid")

    provider: str
    api_key: str


class ProviderKeyStatusResponse(BaseModel):
    """Response payload for provider key status."""

    provider: str | None = None
    has_key: bool = False
    key_last4: str | None = None


@router.get("", response_model=SettingsResponse)
def get_settings(
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
    payload = SettingsService.get_settings(db, user_id)
    payload = UserAIProviderSettingsService.attach_primary_provider_key_status(
        db,
        user_id=user_id,
        payload=payload,
    )
    return SettingsResponse(**payload)


@router.patch("", response_model=SettingsResponse)
def update_settings(
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
    response_payload = SettingsService.update_settings(db, user_id, updates)
    response_payload = UserAIProviderSettingsService.attach_primary_provider_key_status(
        db,
        user_id=user_id,
        payload=response_payload,
    )
    return SettingsResponse(**response_payload)


@router.get("/ai/provider-key", response_model=ProviderKeyStatusResponse)
def get_provider_key_status(
    provider: str | None = None,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Return BYOK status for a provider (defaults to primary provider)."""
    payload = UserAIProviderSettingsService.get_provider_key_status(
        db,
        user_id,
        provider=provider,
    )
    return ProviderKeyStatusResponse(**payload)


@router.put("/ai/provider-key", response_model=ProviderKeyStatusResponse)
def upsert_provider_key(
    payload: ProviderKeyUpdate,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Create or update a BYOK provider API key."""
    response_payload = UserAIProviderSettingsService.upsert_provider_key(
        db,
        user_id,
        provider=payload.provider,
        api_key=payload.api_key,
    )
    return ProviderKeyStatusResponse(**response_payload)


@router.delete("/ai/provider-key", response_model=ProviderKeyStatusResponse)
def delete_provider_key(
    provider: str | None = None,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Soft delete a BYOK provider API key."""
    payload = UserAIProviderSettingsService.delete_provider_key(
        db,
        user_id,
        provider=provider,
    )
    return ProviderKeyStatusResponse(**payload)


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
def get_profile_image(
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
def delete_profile_image(
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
def get_shortcuts_pat(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Return the current shortcuts PAT token, creating one if missing."""
    token = SettingsService.get_or_create_shortcuts_pat(db, user_id)
    return ShortcutsPatResponse(token=token)


@router.post("/shortcuts/pat/rotate", response_model=ShortcutsPatResponse)
def rotate_shortcuts_pat(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Rotate the shortcuts PAT token for the current user."""
    token = SettingsService.rotate_shortcuts_pat(db, user_id)
    return ShortcutsPatResponse(token=token)
