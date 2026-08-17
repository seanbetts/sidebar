"""Tests for durable task-reminder delivery progress."""

from __future__ import annotations

from datetime import UTC, date, datetime

from sqlalchemy import func, select
from sqlalchemy.orm import sessionmaker

from api.models.task_reminder_delivery_state import TaskReminderDeliveryState
from api.models.user_settings import UserSettings
from api.services.task_reminder_delivery_state_service import (
    TaskReminderDeliveryStateService,
)


def test_accepted_delivery_keys_are_idempotent_and_batch_completion_persists(
    test_db,
) -> None:
    test_db.add(UserSettings(user_id="user-123"))
    test_db.commit()
    local_date = date(2026, 1, 15)
    accepted_at = datetime(2026, 1, 15, 9, 0, tzinfo=UTC)

    initial = TaskReminderDeliveryStateService.get_progress(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=local_date,
    )
    assert initial.accepted_delivery_keys == frozenset()
    assert initial.is_complete is False

    TaskReminderDeliveryStateService.mark_delivery_accepted(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=local_date,
        delivery_key="ios:task:task-123",
        accepted_at=accepted_at,
    )
    TaskReminderDeliveryStateService.mark_delivery_accepted(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=local_date,
        delivery_key="ios:task:task-123",
        accepted_at=accepted_at,
    )
    assert TaskReminderDeliveryStateService.mark_batch_completed(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=local_date,
        completed_at=accepted_at,
    )
    test_db.commit()
    test_db.expire_all()

    persisted = TaskReminderDeliveryStateService.get_progress(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=local_date,
    )
    assert persisted.accepted_delivery_keys == frozenset({"ios:task:task-123"})
    assert persisted.is_complete is True


def test_new_local_day_reuses_bounded_state_row(test_db) -> None:
    test_db.add(UserSettings(user_id="user-123"))
    test_db.commit()

    for local_date, delivery_key in (
        (date(2026, 1, 15), "ios:task:first-day"),
        (date(2026, 1, 16), "ios:task:second-day"),
    ):
        accepted_at = datetime.combine(local_date, datetime.min.time(), tzinfo=UTC)
        TaskReminderDeliveryStateService.mark_delivery_accepted(
            test_db,
            user_id="user-123",
            schedule_timezone="Europe/London",
            local_date=local_date,
            delivery_key=delivery_key,
            accepted_at=accepted_at,
        )
        assert TaskReminderDeliveryStateService.mark_batch_completed(
            test_db,
            user_id="user-123",
            schedule_timezone="Europe/London",
            local_date=local_date,
            completed_at=accepted_at,
        )
        test_db.commit()

    row_count = test_db.scalar(select(func.count(TaskReminderDeliveryState.id)))
    assert row_count == 1
    progress = TaskReminderDeliveryStateService.get_progress(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 16),
    )
    assert progress.accepted_delivery_keys == frozenset({"ios:task:second-day"})
    assert progress.is_complete is True


def test_zero_acceptance_cannot_complete_batch(test_db) -> None:
    test_db.add(UserSettings(user_id="user-123"))
    test_db.commit()

    completed = TaskReminderDeliveryStateService.mark_batch_completed(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
        completed_at=datetime(2026, 1, 15, 9, 0, tzinfo=UTC),
    )
    test_db.commit()

    assert completed is False
    progress = TaskReminderDeliveryStateService.get_progress(
        test_db,
        user_id="user-123",
        schedule_timezone="Europe/London",
        local_date=date(2026, 1, 15),
    )
    assert progress.is_complete is False


def test_dispatch_lock_serializes_workers_for_same_user_and_timezone(
    test_db_engine,
) -> None:
    session_factory = sessionmaker(bind=test_db_engine)
    first_db = session_factory()
    second_db = session_factory()
    try:
        assert TaskReminderDeliveryStateService.try_acquire_dispatch_lock(
            first_db,
            user_id="user-123",
            schedule_timezone="Europe/London",
        )
        assert not TaskReminderDeliveryStateService.try_acquire_dispatch_lock(
            second_db,
            user_id="user-123",
            schedule_timezone="Europe/London",
        )

        first_db.commit()

        assert TaskReminderDeliveryStateService.try_acquire_dispatch_lock(
            second_db,
            user_id="user-123",
            schedule_timezone="Europe/London",
        )
    finally:
        first_db.rollback()
        first_db.close()
        second_db.rollback()
        second_db.close()
