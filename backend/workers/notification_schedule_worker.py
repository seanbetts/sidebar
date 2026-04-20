"""Worker loop for scheduled notification evaluation."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from datetime import UTC, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from api.config import settings
from api.db.session import SessionLocal
from api.services.device_token_service import DeviceTokenService
from api.services.morning_digest_service import MorningDigestService
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_policy_service import NotificationPolicyService
from api.services.notification_schedule_service import NotificationScheduleService
from api.services.notification_scheduler_heartbeat_service import (
    NotificationSchedulerHeartbeatService,
)
from api.services.notification_types import NotificationCategory
from api.services.task_reminder_service import TaskReminderService
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger("notification_schedule.worker")
SLEEP_SECONDS = 30
FAILURE_SLEEP_SECONDS = 2


def _mark_recipient_delivered(recipient, *, current_time: datetime) -> None:
    """Persist in-process dedupe markers only after a real successful delivery."""
    try:
        local_now = current_time.astimezone(ZoneInfo(recipient.schedule_timezone))
    except ZoneInfoNotFoundError:
        return

    NotificationScheduleService.mark_emitted_window(
        user_id=recipient.user_id,
        category=recipient.category,
        local_now=local_now,
        scheduled_time=recipient.scheduled_time,
    )
    local_date_iso = local_now.date().isoformat()
    if recipient.category == NotificationCategory.TASK_REMINDER:
        TaskReminderService.mark_emitted_day(
            user_id=recipient.user_id,
            schedule_timezone=recipient.schedule_timezone,
            local_date_iso=local_date_iso,
        )
    elif recipient.category == NotificationCategory.MORNING_DIGEST:
        MorningDigestService.mark_emitted_day(
            user_id=recipient.user_id,
            schedule_timezone=recipient.schedule_timezone,
            local_date_iso=local_date_iso,
        )


def _dispatch_task_reminders(
    db,
    due_users,
    *,
    now: datetime | None = None,
) -> int:
    """Build and deliver due task reminders."""
    environment = DeviceTokenService.normalize_environment(settings.apns_env)
    current_time = now or datetime.now(UTC)
    delivered_count = 0
    for recipient in due_users:
        intent = TaskReminderService.build_daily_reminder(
            db,
            user_id=recipient.user_id,
            schedule_timezone=recipient.schedule_timezone,
            now=current_time,
        )
        if not intent:
            continue

        settings_record = UserSettingsService.get_settings(db, recipient.user_id)
        tokens = DeviceTokenService.list_active_tokens(
            db,
            recipient.user_id,
            environment=environment,
        )
        decision = NotificationPolicyService.evaluate(
            intent,
            settings_record=settings_record,
            device_tokens=tokens,
        )
        if not decision.should_deliver:
            continue

        result = NotificationDeliveryService.deliver_intent(
            intent,
            device_tokens=list(decision.matched_tokens) or tokens,
            db=db,
        )
        if result.sent_count > 0:
            _mark_recipient_delivered(recipient, current_time=current_time)
        delivered_count += result.sent_count
    return delivered_count


def _dispatch_morning_digests(
    db,
    due_users,
    *,
    now: datetime | None = None,
) -> int:
    """Build and deliver due morning digests."""
    environment = DeviceTokenService.normalize_environment(settings.apns_env)
    current_time = now or datetime.now(UTC)
    delivered_count = 0
    for recipient in due_users:
        intent = MorningDigestService.build_digest(
            db,
            user_id=recipient.user_id,
            schedule_timezone=recipient.schedule_timezone,
            now=current_time,
        )
        if not intent:
            continue

        settings_record = UserSettingsService.get_settings(db, recipient.user_id)
        tokens = DeviceTokenService.list_active_tokens(
            db,
            recipient.user_id,
            environment=environment,
        )
        decision = NotificationPolicyService.evaluate(
            intent,
            settings_record=settings_record,
            device_tokens=tokens,
        )
        if not decision.should_deliver:
            continue

        result = NotificationDeliveryService.deliver_intent(
            intent,
            device_tokens=list(decision.matched_tokens) or tokens,
            db=db,
        )
        if result.sent_count > 0:
            _mark_recipient_delivered(recipient, current_time=current_time)
        delivered_count += result.sent_count
    return delivered_count


def process_once(
    *,
    now: datetime | None = None,
    task_dispatcher: Callable[..., int] = _dispatch_task_reminders,
    digest_dispatcher: Callable[..., int] = _dispatch_morning_digests,
) -> dict[str, int]:
    """Evaluate scheduled categories once and dispatch the due recipients."""
    current_time = now or datetime.now(UTC)
    with SessionLocal() as db:
        task_due = NotificationScheduleService.find_due_users(
            db,
            NotificationCategory.TASK_REMINDER,
            now=current_time,
        )
        digest_due = NotificationScheduleService.find_due_users(
            db,
            NotificationCategory.MORNING_DIGEST,
            now=current_time,
        )
        dispatched_task_reminders = task_dispatcher(
            db,
            task_due,
            now=current_time,
        )
        dispatched_morning_digests = digest_dispatcher(
            db,
            digest_due,
            now=current_time,
        )
        db.commit()
        return {
            "task_reminders_due": len(task_due),
            "morning_digests_due": len(digest_due),
            "task_reminders_dispatched": dispatched_task_reminders,
            "morning_digests_dispatched": dispatched_morning_digests,
        }


def execute_once(
    *,
    now: datetime | None = None,
    task_dispatcher: Callable[..., int] = _dispatch_task_reminders,
    digest_dispatcher: Callable[..., int] = _dispatch_morning_digests,
) -> dict[str, int]:
    """Run one scheduler cycle and persist its latest heartbeat state."""
    current_time = now or datetime.now(UTC)
    with SessionLocal() as db:
        NotificationSchedulerHeartbeatService.mark_started(
            db,
            started_at=current_time,
        )
        db.commit()

    try:
        stats = process_once(
            now=current_time,
            task_dispatcher=task_dispatcher,
            digest_dispatcher=digest_dispatcher,
        )
    except Exception as exc:
        failed_at = datetime.now(UTC)
        with SessionLocal() as db:
            NotificationSchedulerHeartbeatService.mark_failed(
                db,
                started_at=current_time,
                failed_at=failed_at,
                error_message=str(exc) or exc.__class__.__name__,
            )
            db.commit()
        raise

    completed_at = datetime.now(UTC)
    with SessionLocal() as db:
        NotificationSchedulerHeartbeatService.mark_completed(
            db,
            started_at=current_time,
            completed_at=completed_at,
            stats=stats,
        )
        db.commit()
    return stats


def worker_loop(sleep_seconds: int = SLEEP_SECONDS) -> None:
    """Run scheduled notification evaluation forever."""
    while True:
        try:
            stats = execute_once()
            if stats["task_reminders_due"] or stats["morning_digests_due"]:
                logger.info("Scheduled notification evaluation: %s", stats)
            time.sleep(sleep_seconds)
        except Exception:
            logger.exception("Notification schedule worker crashed, retrying")
            time.sleep(FAILURE_SLEEP_SECONDS)


def main() -> None:
    """Run the dedicated scheduled-notification worker process."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    worker_loop()


if __name__ == "__main__":
    main()
