"""Worker loop for scheduled notification evaluation."""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from datetime import UTC, datetime

from api.config import settings
from api.db.session import SessionLocal
from api.services.device_token_service import DeviceTokenService
from api.services.morning_digest_service import MorningDigestService
from api.services.notification_delivery_service import NotificationDeliveryService
from api.services.notification_policy_service import NotificationPolicyService
from api.services.notification_schedule_service import NotificationScheduleService
from api.services.notification_types import NotificationCategory
from api.services.task_reminder_service import TaskReminderService
from api.services.user_settings_service import UserSettingsService

logger = logging.getLogger("notification_schedule.worker")
SLEEP_SECONDS = 30


def _dispatch_task_reminders(db, due_users) -> int:
    """Build and deliver due task reminders."""
    environment = DeviceTokenService.normalize_environment(settings.apns_env)
    delivered_count = 0
    for recipient in due_users:
        intent = TaskReminderService.build_daily_reminder(
            db,
            user_id=recipient.user_id,
            schedule_timezone=recipient.schedule_timezone,
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
        )
        delivered_count += result.sent_count
    return delivered_count


def _dispatch_morning_digests(db, due_users) -> int:
    """Build and deliver due morning digests."""
    environment = DeviceTokenService.normalize_environment(settings.apns_env)
    delivered_count = 0
    for recipient in due_users:
        intent = MorningDigestService.build_digest(
            db,
            user_id=recipient.user_id,
            schedule_timezone=recipient.schedule_timezone,
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
        )
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
        dispatched_task_reminders = task_dispatcher(db, task_due)
        dispatched_morning_digests = digest_dispatcher(db, digest_due)
        return {
            "task_reminders_due": len(task_due),
            "morning_digests_due": len(digest_due),
            "task_reminders_dispatched": dispatched_task_reminders,
            "morning_digests_dispatched": dispatched_morning_digests,
        }


def worker_loop(sleep_seconds: int = SLEEP_SECONDS) -> None:
    """Run scheduled notification evaluation forever."""
    while True:
        stats = process_once()
        if stats["task_reminders_due"] or stats["morning_digests_due"]:
            logger.info("Scheduled notification evaluation: %s", stats)
        time.sleep(sleep_seconds)
