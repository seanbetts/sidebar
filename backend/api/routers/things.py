"""Things integration router."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db, set_session_user_id
from api.models.things_bridge import ThingsBridge
from api.services.things_bridge_service import ThingsBridgeService
from api.services.things_bridge_client import ThingsBridgeClient


router = APIRouter(prefix="/things", tags=["things"])


def _bridge_payload(bridge: ThingsBridge, include_token: bool = False) -> dict:
    payload = {
        "bridgeId": str(bridge.id),
        "deviceId": bridge.device_id,
        "deviceName": bridge.device_name,
        "baseUrl": bridge.base_url,
        "capabilities": bridge.capabilities or {},
        "lastSeenAt": bridge.last_seen_at.isoformat() if bridge.last_seen_at else None,
        "updatedAt": bridge.updated_at.isoformat() if bridge.updated_at else None,
    }
    if include_token:
        payload["bridgeToken"] = bridge.bridge_token
    return payload


def _parse_bridge_id(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(value)
    except (TypeError, ValueError):
        raise HTTPException(status_code=400, detail="Invalid bridgeId")


@router.post("/bridges/register")
async def register_bridge(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Register or update a Things bridge."""
    device_id = (request.get("deviceId") or "").strip()
    device_name = (request.get("deviceName") or "").strip()
    base_url = (request.get("baseUrl") or "").strip()
    if not device_id or not device_name or not base_url:
        raise HTTPException(status_code=400, detail="deviceId, deviceName, and baseUrl are required")

    set_session_user_id(db, user_id)
    bridge = ThingsBridgeService.register_bridge(
        db,
        user_id,
        device_id=device_id,
        device_name=device_name,
        base_url=base_url,
        capabilities=request.get("capabilities"),
    )
    return _bridge_payload(bridge, include_token=True)


@router.post("/bridges/heartbeat")
async def heartbeat_bridge(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update bridge last_seen_at timestamp."""
    bridge_id_value = request.get("bridgeId")
    if not bridge_id_value:
        raise HTTPException(status_code=400, detail="bridgeId required")
    bridge_id = _parse_bridge_id(bridge_id_value)

    set_session_user_id(db, user_id)
    bridge = ThingsBridgeService.heartbeat(db, user_id, bridge_id)
    if not bridge:
        raise HTTPException(status_code=404, detail="Bridge not found")
    return {
        "bridgeId": str(bridge.id),
        "lastSeenAt": bridge.last_seen_at.isoformat(),
        "updatedAt": bridge.updated_at.isoformat(),
        "serverTime": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/bridges")
async def list_bridges(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """List bridges for the current user."""
    set_session_user_id(db, user_id)
    bridges = ThingsBridgeService.list_bridges(db, user_id)
    active = ThingsBridgeService.select_active_bridge(db, user_id)
    active_id = str(active.id) if active else None
    return {
        "activeBridgeId": active_id,
        "bridges": [_bridge_payload(bridge) for bridge in bridges],
    }


def _get_active_bridge_or_503(db: Session, user_id: str) -> ThingsBridge:
    bridge = ThingsBridgeService.select_active_bridge(db, user_id)
    if not bridge:
        raise HTTPException(status_code=503, detail="No active Things bridge available")
    return bridge


@router.get("/lists/{scope}")
async def get_things_list(
    scope: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch a Things list from the active bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.get_list(scope)


@router.post("/apply")
async def apply_things_operation(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Apply an operation via the active Things bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.apply(request)
