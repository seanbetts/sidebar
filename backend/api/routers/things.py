"""Things integration router."""
import asyncio
import uuid
from pathlib import Path
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import SessionLocal, get_db, set_session_user_id
from api.models.things_bridge import ThingsBridge
from api.services.things_bridge_service import ThingsBridgeService
from api.services.things_bridge_client import ThingsBridgeClient
from api.services.things_snapshot_service import ThingsSnapshotService
from api.services.user_settings_service import UserSettingsService
from api.services.things_bridge_install_service import ThingsBridgeInstallService
from api.config import settings


router = APIRouter(prefix="/things", tags=["things"])


async def _update_snapshot_async(user_id: str, today_payload: dict) -> None:
    with SessionLocal() as db:
        set_session_user_id(db, user_id)
        bridge = ThingsBridgeService.select_active_bridge(db, user_id)
        if not bridge:
            return
        client = ThingsBridgeClient(bridge)
        try:
            upcoming = await client.get_list("upcoming")
            tomorrow_tasks = ThingsSnapshotService.filter_tomorrow(upcoming.get("tasks", []))
            completed_today_payload = await client.completed_today()
            completed_today = completed_today_payload.get("tasks", [])
            snapshot = ThingsSnapshotService.build_snapshot(
                today_tasks=today_payload.get("tasks", []),
                tomorrow_tasks=tomorrow_tasks,
                completed_today=completed_today,
                areas=upcoming.get("areas") or today_payload.get("areas", []),
                projects=upcoming.get("projects") or today_payload.get("projects", []),
            )
            UserSettingsService.update_things_snapshot(db, user_id, snapshot)
        except Exception:
            return


def _update_snapshot_background(user_id: str, today_payload: dict) -> None:
    asyncio.run(_update_snapshot_async(user_id, today_payload))


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
    x_bridge_id: str | None = Header(default=None),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update bridge last_seen_at timestamp."""
    bridge_id_value = request.get("bridgeId") or x_bridge_id
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


@router.post("/bridges/install-script")
async def install_script(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return a one-time install script for the Things bridge."""
    set_session_user_id(db, user_id)
    install = ThingsBridgeInstallService.create_token(db, user_id)
    token = install["token"]
    backend_url = settings.things_bridge_backend_url.rstrip("/")
    bridge_path = Path(__file__).resolve().parents[3] / "bridge" / "things_bridge.py"
    if not bridge_path.exists():
        raise HTTPException(status_code=500, detail="Bridge script not found")
    bridge_source = bridge_path.read_text(encoding="utf-8")
    script = f"""#!/bin/bash
set -euo pipefail

DEVICE_NAME="$(scutil --get ComputerName || hostname)"
DEVICE_ID="$(echo "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
BASE_URL="http://127.0.0.1:8787"
INSTALL_TOKEN="{token}"
BACKEND_URL="{backend_url}"
BRIDGE_DIR="$HOME/.sidebar/bridge"
BRIDGE_PATH="$BRIDGE_DIR/things_bridge.py"
VENV_PATH="$BRIDGE_DIR/venv"

mkdir -p "$BRIDGE_DIR"

cat > "$BRIDGE_PATH" <<'PY'
{bridge_source}
PY

if [[ ! -d "$VENV_PATH" ]]; then
  /usr/bin/python3 -m venv "$VENV_PATH"
  "$VENV_PATH/bin/pip" install --upgrade pip >/dev/null
  "$VENV_PATH/bin/pip" install fastapi uvicorn >/dev/null
fi

echo "Registering Things bridge for $DEVICE_NAME..."
RESPONSE="$(curl -s -X POST "$BACKEND_URL/api/things/bridges/install" \\
  -H "X-Install-Token: $INSTALL_TOKEN" \\
  -H "Content-Type: application/json" \\
  -d "{{\\"deviceId\\":\\"$DEVICE_ID\\",\\"deviceName\\":\\"$DEVICE_NAME\\",\\"baseUrl\\":\\"$BASE_URL\\",\\"capabilities\\":{{\\"read\\":true,\\"write\\":true}}}}")"

BRIDGE_ID="$(echo "$RESPONSE" | python -c 'import json,sys; print(json.load(sys.stdin).get("bridgeId",""))')"
BRIDGE_TOKEN="$(echo "$RESPONSE" | python -c 'import json,sys; print(json.load(sys.stdin).get("bridgeToken",""))')"

if [[ -z "$BRIDGE_ID" || -z "$BRIDGE_TOKEN" ]]; then
  echo "Failed to register bridge. Response: $RESPONSE"
  exit 1
fi

security add-generic-password -a "bridge-id" -s "sidebar-things-bridge" -w "$BRIDGE_ID" -U >/dev/null 2>&1
security add-generic-password -a "bridge-token" -s "sidebar-things-bridge" -w "$BRIDGE_TOKEN" -U >/dev/null 2>&1

PLIST_PATH="$HOME/Library/LaunchAgents/com.sidebar.things-bridge.plist"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.sidebar.things-bridge</string>
  <key>ProgramArguments</key>
  <array>
    <string>$VENV_PATH/bin/python</string>
    <string>$BRIDGE_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>EnvironmentVariables</key>
  <dict>
    <key>THINGS_BRIDGE_PORT</key>
    <string>8787</string>
    <key>THINGS_BACKEND_URL</key>
    <string>{backend_url}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/sidebar-things-bridge.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/sidebar-things-bridge.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"

echo "Things bridge installed and running."
"""
    return Response(
        script,
        media_type="text/plain",
        headers={"Content-Disposition": "attachment; filename=install-things-bridge.command"},
    )


@router.post("/bridges/install")
async def install_bridge(request: dict, x_install_token: str | None = Header(default=None), db: Session = Depends(get_db)):
    """Install a Things bridge using a one-time token."""
    token = x_install_token or request.get("installToken")
    if not token:
        raise HTTPException(status_code=400, detail="install token required")
    record = ThingsBridgeInstallService.consume_token(db, token)
    if not record:
        raise HTTPException(status_code=401, detail="Invalid or expired install token")

    device_id = (request.get("deviceId") or "").strip()
    device_name = (request.get("deviceName") or "").strip()
    base_url = (request.get("baseUrl") or "").strip()
    if not device_id or not device_name or not base_url:
        raise HTTPException(status_code=400, detail="deviceId, deviceName, and baseUrl are required")

    set_session_user_id(db, record.user_id)
    bridge = ThingsBridgeService.register_bridge(
        db,
        record.user_id,
        device_id=device_id,
        device_name=device_name,
        base_url=base_url,
        capabilities=request.get("capabilities"),
    )
    return {
        "bridgeId": str(bridge.id),
        "bridgeToken": bridge.bridge_token,
    }


@router.get("/bridges/status")
async def bridge_status(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return current active bridge status for the user."""
    set_session_user_id(db, user_id)
    bridges = ThingsBridgeService.list_bridges(db, user_id)
    active = ThingsBridgeService.select_active_bridge(db, user_id)
    return {
        "activeBridgeId": str(active.id) if active else None,
        "activeBridge": _bridge_payload(active) if active else None,
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
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch a Things list from the active bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    response = await client.get_list(scope)
    if scope == "today":
        background_tasks.add_task(_update_snapshot_background, user_id, response)
    return response


@router.get("/search")
async def search_things_tasks(
    query: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Search Things tasks via the active bridge."""
    query = query.strip()
    if not query:
        raise HTTPException(status_code=400, detail="query required")
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.search(query)


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


@router.post("/bridges/url-token")
async def set_url_token(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Store the Things URL auth token on the active bridge."""
    token = (request.get("token") or "").strip()
    if not token:
        raise HTTPException(status_code=400, detail="token required")
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.set_url_token(token)


@router.get("/projects/{project_id}/tasks")
async def get_project_tasks(
    project_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch tasks for a Things project via the active bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.project_tasks(project_id)


@router.get("/areas/{area_id}/tasks")
async def get_area_tasks(
    area_id: str,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch tasks for a Things area via the active bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.area_tasks(area_id)


@router.get("/counts")
async def get_counts(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch Things counts via the active bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.counts()


@router.get("/diagnostics")
async def get_diagnostics(
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Fetch Things bridge diagnostics via the active bridge."""
    set_session_user_id(db, user_id)
    bridge = _get_active_bridge_or_503(db, user_id)
    client = ThingsBridgeClient(bridge)
    return await client.diagnostics()
