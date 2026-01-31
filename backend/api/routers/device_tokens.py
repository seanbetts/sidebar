"""Device token router for push notifications."""
# ruff: noqa: B008

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db, set_session_user_id
from api.services.device_token_service import DeviceTokenService

router = APIRouter(prefix="/device-tokens", tags=["device-tokens"])


def _token_payload(record) -> dict:
    return {
        "id": str(record.id),
        "token": record.token,
        "platform": record.platform,
        "environment": record.environment,
        "createdAt": record.created_at.isoformat() if record.created_at else None,
        "updatedAt": record.updated_at.isoformat() if record.updated_at else None,
        "disabledAt": record.disabled_at.isoformat() if record.disabled_at else None,
    }


@router.post("")
def register_device_token(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Register a device token for push notifications."""
    set_session_user_id(db, user_id)
    token = str(request.get("token") or "")
    platform = str(request.get("platform") or "")
    environment = str(request.get("environment") or "")
    record = DeviceTokenService.register_token(
        db,
        user_id,
        token=token,
        platform=platform,
        environment=environment,
    )
    db.commit()
    return _token_payload(record)


@router.delete("")
def disable_device_token(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Disable a device token for push notifications."""
    set_session_user_id(db, user_id)
    token = str(request.get("token") or "")
    record = DeviceTokenService.disable_token(db, user_id, token)
    db.commit()
    return {
        "disabled": bool(record),
        "disabledAt": record.disabled_at.isoformat()
        if record and record.disabled_at
        else None,
    }
