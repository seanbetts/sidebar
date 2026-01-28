"""Task change notification orchestration."""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import UTC, datetime

from api.services.task_service import TaskCounts


@dataclass
class TaskChangeNotifications:
    """Notification payloads for task changes."""

    event: dict | None
    badge_count: int | None


class TaskChangeService:
    """Build task change notifications with debounce."""

    SSE_DEBOUNCE_SECONDS = 1.0
    PUSH_DEBOUNCE_SECONDS = 60.0

    _last_sse_sent: dict[str, float] = {}
    _last_push_sent: dict[str, float] = {}

    @classmethod
    def build_notifications(
        cls,
        *,
        user_id: str,
        before: TaskCounts,
        after: TaskCounts,
    ) -> TaskChangeNotifications:
        """Build notification payloads for task changes.

        Args:
            user_id: Current user ID.
            before: Task counts before changes.
            after: Task counts after changes.

        Returns:
            TaskChangeNotifications with optional SSE event and badge count.
        """
        if before.today == after.today:
            return TaskChangeNotifications(event=None, badge_count=None)

        now = time.monotonic()
        event = None
        last_sse = cls._last_sse_sent.get(user_id, 0.0)
        if now - last_sse >= cls.SSE_DEBOUNCE_SECONDS:
            cls._last_sse_sent[user_id] = now
            event = {
                "scope": "tasks",
                "hints": {
                    "todayCountChanged": True,
                    "changedScopes": ["today"],
                },
                "occurredAt": datetime.now(UTC).isoformat(),
            }

        badge_count = None
        last_push = cls._last_push_sent.get(user_id, 0.0)
        if now - last_push >= cls.PUSH_DEBOUNCE_SECONDS:
            cls._last_push_sent[user_id] = now
            badge_count = after.today

        return TaskChangeNotifications(event=event, badge_count=badge_count)
