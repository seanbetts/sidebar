"""Persist task-reminder delivery progress across worker restarts."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session
from sqlalchemy.orm.attributes import flag_modified

from api.models.task_reminder_delivery_state import TaskReminderDeliveryState


@dataclass(frozen=True, slots=True)
class TaskReminderDeliveryProgress:
    """Accepted intent keys and completion state for one local day."""

    accepted_delivery_keys: frozenset[str]
    is_complete: bool


class TaskReminderDeliveryStateService:
    """Own durable task-reminder progress and dispatch serialization."""

    @staticmethod
    def get_progress(
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date: date,
    ) -> TaskReminderDeliveryProgress:
        """Return persisted progress when it belongs to the requested local day."""
        state = db.scalar(
            select(TaskReminderDeliveryState).where(
                TaskReminderDeliveryState.user_id == user_id,
                TaskReminderDeliveryState.schedule_timezone == schedule_timezone,
            )
        )
        if state is None or state.local_date != local_date:
            return TaskReminderDeliveryProgress(frozenset(), False)
        return TaskReminderDeliveryProgress(
            accepted_delivery_keys=frozenset(state.accepted_delivery_keys),
            is_complete=state.completed_at is not None,
        )

    @staticmethod
    def mark_delivery_accepted(
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date: date,
        delivery_key: str,
        accepted_at: datetime | None = None,
    ) -> TaskReminderDeliveryState:
        """Record one APNs-accepted intent without completing the whole batch."""
        current_time = accepted_at or datetime.now(UTC)
        state = TaskReminderDeliveryStateService._get_or_create_locked_state(
            db,
            user_id=user_id,
            schedule_timezone=schedule_timezone,
            local_date=local_date,
            current_time=current_time,
        )
        TaskReminderDeliveryStateService._reset_for_newer_local_day(
            state,
            local_date=local_date,
            current_time=current_time,
        )
        if delivery_key not in state.accepted_delivery_keys:
            state.accepted_delivery_keys.append(delivery_key)
            flag_modified(state, "accepted_delivery_keys")
        state.updated_at = current_time
        db.flush()
        return state

    @staticmethod
    def mark_batch_completed(
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date: date,
        completed_at: datetime | None = None,
    ) -> bool:
        """Complete a local-day batch only when at least one intent was accepted."""
        state = db.scalar(
            select(TaskReminderDeliveryState)
            .where(
                TaskReminderDeliveryState.user_id == user_id,
                TaskReminderDeliveryState.schedule_timezone == schedule_timezone,
            )
            .with_for_update()
        )
        if (
            state is None
            or state.local_date != local_date
            or not state.accepted_delivery_keys
        ):
            return False
        current_time = completed_at or datetime.now(UTC)
        state.completed_at = current_time
        state.updated_at = current_time
        db.flush()
        return True

    @staticmethod
    def try_acquire_dispatch_lock(
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
    ) -> bool:
        """Acquire a transaction lock that prevents concurrent batch dispatch."""
        lock_identity = f"task-reminder:{user_id}:{schedule_timezone}"
        acquired = db.scalar(
            select(
                func.pg_try_advisory_xact_lock(func.hashtextextended(lock_identity, 0))
            )
        )
        return bool(acquired)

    @staticmethod
    def _get_or_create_locked_state(
        db: Session,
        *,
        user_id: str,
        schedule_timezone: str,
        local_date: date,
        current_time: datetime,
    ) -> TaskReminderDeliveryState:
        """Create the bounded user/timezone row, then lock it for mutation."""
        db.execute(
            insert(TaskReminderDeliveryState)
            .values(
                id=uuid.uuid4(),
                user_id=user_id,
                schedule_timezone=schedule_timezone,
                local_date=local_date,
                accepted_delivery_keys=[],
                completed_at=None,
                created_at=current_time,
                updated_at=current_time,
            )
            .on_conflict_do_nothing(
                constraint="uq_task_reminder_delivery_states_user_timezone"
            )
        )
        state = db.scalar(
            select(TaskReminderDeliveryState)
            .where(
                TaskReminderDeliveryState.user_id == user_id,
                TaskReminderDeliveryState.schedule_timezone == schedule_timezone,
            )
            .with_for_update()
        )
        if state is None:  # pragma: no cover - database invariant
            raise RuntimeError("Task reminder delivery state could not be created")
        return state

    @staticmethod
    def _reset_for_newer_local_day(
        state: TaskReminderDeliveryState,
        *,
        local_date: date,
        current_time: datetime,
    ) -> None:
        """Reuse a bounded state row while rejecting stale day regressions."""
        if state.local_date > local_date:
            raise ValueError("Task reminder delivery local date cannot move backwards")
        if state.local_date == local_date:
            return
        state.local_date = local_date
        state.accepted_delivery_keys = []
        state.completed_at = None
        state.updated_at = current_time
        flag_modified(state, "accepted_delivery_keys")
