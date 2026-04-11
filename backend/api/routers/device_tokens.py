"""Device token router for push notifications."""
# ruff: noqa: B008

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db, set_session_user_id
from api.services.device_token_service import DeviceTokenService

router = APIRouter(prefix="/device-tokens", tags=["device-tokens"])


class DeviceTokenRegisterRequest(BaseModel):
    """Request payload for registering a device token."""

    model_config = ConfigDict(extra="forbid")

    installation_id: str | None = None
    token: str
    platform: str
    environment: str
    capabilities: dict[str, bool] | None = None


class DeviceTokenDisableRequest(BaseModel):
    """Request payload for disabling a device token."""

    model_config = ConfigDict(extra="forbid")

    installation_id: str | None = None
    token: str | None = None


class DeviceTokenPresenceRequest(BaseModel):
    """Request payload for updating token presence metadata."""

    model_config = ConfigDict(extra="forbid")

    installation_id: str | None = None
    token: str | None = None
    is_foreground: bool
    last_seen_at: datetime | None = None


def _token_payload(record) -> dict:
    return {
        "id": str(record.id),
        "installationId": record.installation_id,
        "token": record.token,
        "platform": record.platform,
        "environment": record.environment,
        "capabilities": record.capabilities or {},
        "isForeground": bool(record.is_foreground),
        "lastSeenAt": record.last_seen_at.isoformat() if record.last_seen_at else None,
        "createdAt": record.created_at.isoformat() if record.created_at else None,
        "updatedAt": record.updated_at.isoformat() if record.updated_at else None,
        "disabledAt": record.disabled_at.isoformat() if record.disabled_at else None,
    }


@router.post("")
def register_device_token(
    request: DeviceTokenRegisterRequest,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Register a device token for push notifications."""
    set_session_user_id(db, user_id)
    record = DeviceTokenService.register_token(
        db,
        user_id,
        installation_id=request.installation_id,
        token=request.token,
        platform=request.platform,
        environment=request.environment,
        capabilities=request.capabilities,
    )
    db.commit()
    return _token_payload(record)


@router.delete("")
def disable_device_token(
    request: DeviceTokenDisableRequest,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Disable a device token for push notifications."""
    set_session_user_id(db, user_id)
    record = DeviceTokenService.disable_token(
        db,
        user_id,
        request.token or "",
        installation_id=request.installation_id,
    )
    db.commit()
    return {
        "disabled": bool(record),
    }


@router.post("/presence")
def update_device_token_presence(
    request: DeviceTokenPresenceRequest,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update presence metadata for an existing device token."""
    set_session_user_id(db, user_id)
    record = DeviceTokenService.update_presence(
        db,
        user_id,
        installation_id=request.installation_id,
        token=request.token,
        is_foreground=request.is_foreground,
        last_seen_at=request.last_seen_at,
    )
    if not record:
        raise HTTPException(status_code=404, detail="device token not found")
    db.commit()
    return _token_payload(record)
