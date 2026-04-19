"""Internal-only notification diagnostics router."""
# ruff: noqa: B008

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import PermissionDeniedError
from api.services.internal_access_service import InternalAccessService
from api.services.notification_diagnostics_service import (
    NotificationDiagnosticsService,
)

router = APIRouter(prefix="/internal/notification-diagnostics", tags=["internal"])


class InternalNotificationDiagnosticsAccountSummaryResponse(BaseModel):
    """Current account summary returned in the diagnostics snapshot."""

    user_id: str


class InternalNotificationDiagnosticsInstallationResponse(BaseModel):
    """Installation row returned in the diagnostics snapshot."""

    installation_id: str
    user_id: str
    platform: str
    token_suffix: str | None = None
    is_foreground: bool | None = None


class InternalNotificationDiagnosticsDeliveryResponse(BaseModel):
    """Delivery audit row returned in the diagnostics snapshot."""

    created_at: str
    user_id: str
    installation_id: str | None = None
    notification_kind: str
    platform: str | None = None
    token_suffix: str | None = None
    delivery_result: str
    skip_reason: str | None = None
    apns_status_code: int | None = None
    apns_reason: str | None = None
    apns_topic: str | None = None
    apns_environment: str | None = None


class InternalNotificationDiagnosticsSnapshotResponse(BaseModel):
    """Snapshot payload for the signed-in user's diagnostics view."""

    can_access_internal_diagnostics: bool
    account_summary: InternalNotificationDiagnosticsAccountSummaryResponse | None = None
    installations: list[InternalNotificationDiagnosticsInstallationResponse]
    recent_delivery: list[InternalNotificationDiagnosticsDeliveryResponse]


class InternalNotificationTestPushResponse(BaseModel):
    """Response payload for a single-installation test push."""

    installation_id: str
    accepted: bool
    message: str | None = None


def _require_internal_diagnostics_access(user_id: str) -> None:
    if not InternalAccessService.can_access_internal_diagnostics(user_id):
        raise PermissionDeniedError("internal diagnostics")


@router.get("", response_model=InternalNotificationDiagnosticsSnapshotResponse)
def get_notification_diagnostics(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Return the signed-in user's notification diagnostics snapshot."""
    _require_internal_diagnostics_access(user_id)
    payload = NotificationDiagnosticsService.get_snapshot(db, user_id=user_id)
    return InternalNotificationDiagnosticsSnapshotResponse(**payload)


@router.post(
    "/installations/{installation_id}/test-push",
    response_model=InternalNotificationTestPushResponse,
)
def send_test_push_to_installation(
    installation_id: str,
    db: Session = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
):
    """Send a user-scoped internal test push to one installation."""
    _require_internal_diagnostics_access(user_id)
    payload = NotificationDiagnosticsService.send_test_push_to_installation(
        db,
        user_id=user_id,
        installation_id=installation_id,
    )
    return InternalNotificationTestPushResponse(**payload)
