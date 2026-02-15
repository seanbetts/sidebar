from datetime import date

import plistlib
from api.models.task import Task
from api.services.recurrence_service import RecurrenceService
from api.services.recurrence_plist_parser import RecurrencePlistParser


def test_parse_plist_recurrence_rule():
    payload = {"fu": 16, "fa": 2, "of": {"dy": 1}, "sr": "2025-01-01"}
    plist_bytes = plistlib.dumps(payload)

    rule = RecurrencePlistParser.parse_recurrence_rule(plist_bytes)

    assert rule is not None
    assert rule["type"] == "daily"
    assert rule["interval"] == 2


def test_calculate_next_occurrence_daily():
    rule = {"type": "daily", "interval": 3}
    next_date = RecurrenceService.calculate_next_occurrence(rule, date(2026, 1, 1))
    assert next_date == date(2026, 1, 4)


def test_calculate_next_occurrence_weekly():
    rule = {"type": "weekly", "interval": 2, "weekday": 1}
    next_date = RecurrenceService.calculate_next_occurrence(rule, date(2026, 1, 5))
    assert next_date == date(2026, 1, 19)


def test_calculate_next_occurrence_monthly_clamps():
    rule = {"type": "monthly", "interval": 1, "day_of_month": 31}
    next_date = RecurrenceService.calculate_next_occurrence(rule, date(2026, 1, 31))
    assert next_date == date(2026, 2, 28)


def test_complete_repeating_task_is_idempotent(test_db):
    task = Task(
        user_id="user",
        title="Repeat",
        status="today",
        recurrence_rule={"type": "daily", "interval": 1},
        repeating=True,
        repeat_template=True,
    )
    test_db.add(task)
    test_db.commit()
    test_db.refresh(task)

    first = RecurrenceService.complete_repeating_task(test_db, task)
    test_db.commit()
    assert first is not None

    second = RecurrenceService.complete_repeating_task(test_db, task)
    test_db.commit()
    assert second is not None
    assert first.id == second.id


def test_complete_repeating_task_uses_next_instance_date(test_db):
    task = Task(
        user_id="user",
        title="Repeat",
        status="today",
        deadline=date(2026, 1, 1),
        recurrence_rule={"type": "daily", "interval": 1},
        repeating=True,
        repeat_template=True,
        next_instance_date=date(2026, 1, 2),
    )
    test_db.add(task)
    test_db.commit()
    test_db.refresh(task)

    task.deadline = date(2026, 1, 10)
    test_db.commit()
    test_db.refresh(task)

    next_task = RecurrenceService.complete_repeating_task(test_db, task)
    test_db.commit()

    assert next_task is not None
    assert next_task.deadline == date(2026, 1, 2)
    assert next_task.next_instance_date == date(2026, 1, 3)
