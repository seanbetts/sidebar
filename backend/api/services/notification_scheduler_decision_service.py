"""Write and read helpers for scheduler user decision diagnostics."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy.orm import Session

from api.models.notification_scheduler_decision import NotificationSchedulerDecision


class NotificationSchedulerDecisionService:
    """Persist user-scoped scheduler decisions for internal diagnostics."""

    WORKER_NAME = "notification_schedule"
    RECENT_USER_LIMIT = 25

    @classmethod
    def list_recent_for_user(
        cls,
        db: Session,
        *,
        user_id: str,
        limit: int | None = None,
    ) -> list[NotificationSchedulerDecision]:
        """Return recent scheduler decisions for one user, newest first."""
        resolved_limit = limit or cls.RECENT_USER_LIMIT
        return (
            db.query(NotificationSchedulerDecision)
            .filter(NotificationSchedulerDecision.user_id == user_id)
            .order_by(NotificationSchedulerDecision.created_at.desc())
            .limit(resolved_limit)
            .all()
        )

    @classmethod
    def record(
        cls,
        db: Session,
        *,
        run_started_at: datetime,
        user_id: str,
        notification_kind: str,
        decision_stage: str,
        decision_reason: str,
        scheduled_time: str | None = None,
        schedule_timezone: str | None = None,
        local_now: datetime | None = None,
        detail: str | None = None,
    ) -> NotificationSchedulerDecision:
        """Persist one user-scoped scheduler decision row."""
        row = NotificationSchedulerDecision(
            worker_name=cls.WORKER_NAME,
            run_started_at=run_started_at,
            user_id=user_id,
            notification_kind=notification_kind,
            decision_stage=decision_stage,
            decision_reason=decision_reason,
            scheduled_time=scheduled_time,
            schedule_timezone=schedule_timezone,
            local_now=local_now,
            detail=detail,
        )
        db.add(row)
        db.flush()
        return row
