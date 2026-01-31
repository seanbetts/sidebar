"""Recurrence calculation and next-instance creation."""

from __future__ import annotations

from calendar import monthrange
from datetime import UTC, date, datetime, timedelta

from sqlalchemy.orm import Session

from api.models.task import Task


class RecurrenceService:
    """Service for recurrence computations and task duplication."""

    @staticmethod
    def next_instance_date(task: Task, *, base_date: date | None = None) -> date | None:
        """Calculate the next instance date for a repeating task."""
        if not task.recurrence_rule or not task.repeating:
            return None
        if task.next_instance_date:
            return task.next_instance_date
        anchor = (
            RecurrenceService._parse_anchor_date(task.recurrence_rule)
            or base_date
            or task.deadline
            or date.today()
        )
        return RecurrenceService.calculate_next_occurrence(task.recurrence_rule, anchor)

    @staticmethod
    def calculate_next_occurrence(rule: dict, from_date: date) -> date:
        """Calculate the next occurrence date for a recurrence rule.

        Args:
            rule: Recurrence rule dict.
            from_date: Date to calculate from.

        Returns:
            Next occurrence date.
        """
        rule_type = rule.get("type")
        interval = max(1, int(rule.get("interval") or 1))

        if rule_type == "daily":
            return from_date + timedelta(days=interval)
        if rule_type == "weekly":
            target = int(rule.get("weekday", 0))
            python_weekday = (target + 6) % 7
            days_ahead = (python_weekday - from_date.weekday()) % 7
            if days_ahead == 0:
                days_ahead = 7 * interval
            else:
                days_ahead += 7 * (interval - 1)
            return from_date + timedelta(days=days_ahead)
        if rule_type == "monthly":
            target_day = int(rule.get("day_of_month") or from_date.day)
            month = from_date.month - 1 + interval
            year = from_date.year + month // 12
            month = month % 12 + 1
            max_day = monthrange(year, month)[1]
            return date(year, month, min(target_day, max_day))

        raise ValueError(f"Unknown recurrence type: {rule_type}")

    @staticmethod
    def complete_repeating_task(db: Session, task: Task) -> Task | None:
        """Create the next instance for a repeating task.

        Args:
            db: Database session.
            task: Completed task.

        Returns:
            Newly created or existing next task instance.
        """
        if not task.recurrence_rule:
            return None

        completed_at = task.completed_at.date() if task.completed_at else date.today()
        if task.next_instance_date:
            next_date = task.next_instance_date
        else:
            anchor_date = (
                RecurrenceService._parse_anchor_date(task.recurrence_rule)
                or task.deadline
                or completed_at
            )
            next_date = RecurrenceService.calculate_next_occurrence(
                task.recurrence_rule, anchor_date
            )
        template_id = task.repeat_template_id or task.id

        existing = (
            db.query(Task)
            .filter(
                Task.repeat_template_id == template_id,
                Task.deadline == next_date,
                Task.deleted_at.is_(None),
            )
            .one_or_none()
        )
        if existing:
            return existing

        now = datetime.now(UTC)
        next_instance = Task(
            user_id=task.user_id,
            project_id=task.project_id,
            group_id=task.group_id,
            title=task.title,
            notes=task.notes,
            status="inbox",
            deadline=next_date,
            repeating=True,
            repeat_template=False,
            repeat_template_id=template_id,
            recurrence_rule=task.recurrence_rule,
            next_instance_date=RecurrenceService.calculate_next_occurrence(
                task.recurrence_rule, next_date
            ),
            created_at=now,
            updated_at=now,
            completed_at=None,
            trashed_at=None,
            deleted_at=None,
        )
        db.add(next_instance)
        db.flush()
        return next_instance

    @staticmethod
    def _parse_anchor_date(rule: dict | None) -> date | None:
        if not rule:
            return None
        raw = rule.get("anchor_date")
        if not raw:
            return None
        try:
            return datetime.fromisoformat(str(raw).replace("Z", "+00:00")).date()
        except ValueError:
            return None
