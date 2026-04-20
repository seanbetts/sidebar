"""Read and action service for internal notification diagnostics."""

from __future__ import annotations

from api.exceptions import NotFoundError
from api.models.notification_diagnostics_audit import NotificationDiagnosticsAudit
from api.services.device_installation_service import DeviceInstallationService
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_scheduler_heartbeat_service import (
    NotificationSchedulerHeartbeatService,
)
from api.services.notification_types import (
    NotificationCategory,
    NotificationDeliveryMode,
    NotificationIntent,
)


class NotificationDiagnosticsService:
    """Build notification diagnostics snapshots and installation test pushes."""

    RECENT_DELIVERY_LIMIT = 25

    @staticmethod
    def get_snapshot(db, *, user_id: str) -> dict:
        """Return the signed-in user's diagnostics snapshot."""
        installations = DeviceInstallationService.list_active_installations_for_user(
            db,
            user_id=user_id,
        )
        recent_delivery = (
            db.query(NotificationDiagnosticsAudit)
            .filter(NotificationDiagnosticsAudit.user_id == user_id)
            .order_by(NotificationDiagnosticsAudit.created_at.desc())
            .limit(NotificationDiagnosticsService.RECENT_DELIVERY_LIMIT)
            .all()
        )
        scheduler = NotificationSchedulerHeartbeatService.get_status(db)
        return {
            "can_access_internal_diagnostics": True,
            "account_summary": {"user_id": user_id},
            "scheduler": (
                {
                    "worker_name": scheduler.worker_name,
                    "last_started_at": (
                        scheduler.last_started_at.isoformat()
                        if scheduler.last_started_at
                        else None
                    ),
                    "last_completed_at": (
                        scheduler.last_completed_at.isoformat()
                        if scheduler.last_completed_at
                        else None
                    ),
                    "last_status": scheduler.last_status,
                    "last_error": scheduler.last_error,
                    "last_task_reminders_due": scheduler.last_task_reminders_due,
                    "last_task_reminders_dispatched": (
                        scheduler.last_task_reminders_dispatched
                    ),
                    "last_morning_digests_due": scheduler.last_morning_digests_due,
                    "last_morning_digests_dispatched": (
                        scheduler.last_morning_digests_dispatched
                    ),
                }
                if scheduler is not None
                else None
            ),
            "installations": [
                {
                    "installation_id": installation.installation_id,
                    "user_id": user_id,
                    "platform": installation.platform,
                    "token_suffix": str(installation.token or "")[-8:] or None,
                    "is_foreground": installation.is_foreground,
                }
                for installation in installations
            ],
            "recent_delivery": [
                {
                    "created_at": audit.created_at.isoformat(),
                    "user_id": audit.user_id,
                    "installation_id": audit.installation_id,
                    "notification_kind": audit.notification_kind,
                    "platform": audit.platform,
                    "token_suffix": audit.token_suffix,
                    "delivery_result": audit.delivery_result,
                    "skip_reason": audit.skip_reason,
                    "apns_status_code": audit.apns_status_code,
                    "apns_reason": audit.apns_reason,
                    "apns_topic": audit.apns_topic,
                    "apns_environment": audit.apns_env,
                }
                for audit in recent_delivery
            ],
        }

    @staticmethod
    def send_test_push_to_installation(
        db,
        *,
        user_id: str,
        installation_id: str,
    ) -> dict:
        """Send one alert test push to an installation owned by the signed-in user."""
        installation = next(
            (
                candidate
                for candidate in (
                    DeviceInstallationService.list_active_installations_for_user(
                        db,
                        user_id=user_id,
                    )
                )
                if candidate.installation_id == installation_id
            ),
            None,
        )
        if installation is None:
            raise NotFoundError("Device installation", installation_id)

        result = NotificationDeliveryService.deliver_intent(
            NotificationIntent(
                user_id=user_id,
                category=NotificationCategory.TEST_PUSH,
                delivery_mode=NotificationDeliveryMode.ALERT,
                title="sideBar test push",
                body="Internal notification diagnostics test push.",
                route="sidebar://settings/internal-notification-diagnostics",
            ),
            device_tokens=[installation],
            db=db,
        )
        db.commit()

        primary_outcome = result.outcomes[0] if result.outcomes else None
        accepted = bool(primary_outcome and primary_outcome.accepted)
        message = None
        if primary_outcome is not None:
            message = primary_outcome.reason or (
                "accepted" if primary_outcome.accepted else None
            )

        return {
            "installation_id": installation.installation_id,
            "accepted": accepted,
            "message": message,
        }
