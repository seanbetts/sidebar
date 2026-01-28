from api.services.task_change_service import TaskChangeService
from api.services.task_service import TaskCounts


def _counts(today: int) -> TaskCounts:
    return TaskCounts(
        inbox=0,
        today=today,
        upcoming=0,
        completed=0,
        project_counts=[],
        group_counts=[],
    )


def test_task_change_notifications_emitted_on_today_change():
    TaskChangeService._last_sse_sent.clear()
    TaskChangeService._last_push_sent.clear()

    before = _counts(1)
    after = _counts(2)
    notifications = TaskChangeService.build_notifications(
        user_id="user-123",
        before=before,
        after=after,
    )

    assert notifications.event is not None
    assert notifications.badge_count == 2


def test_task_change_notifications_skipped_when_unchanged():
    TaskChangeService._last_sse_sent.clear()
    TaskChangeService._last_push_sent.clear()

    before = _counts(3)
    after = _counts(3)
    notifications = TaskChangeService.build_notifications(
        user_id="user-123",
        before=before,
        after=after,
    )

    assert notifications.event is None
    assert notifications.badge_count is None
