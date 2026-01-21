import uuid
from datetime import date

import plistlib
from api.db.base import Base
from api.models.task import Task
from api.services.recurrence_service import RecurrenceService
from api.services.things_recurrence_parser import ThingsRecurrenceParser
from sqlalchemy import text
from sqlalchemy.orm import sessionmaker


def _build_session(test_db_engine):
    connection = test_db_engine.connect().execution_options(
        isolation_level="AUTOCOMMIT"
    )
    schema = f"test_{uuid.uuid4().hex}"

    connection.execute(text(f'CREATE SCHEMA "{schema}"'))
    connection.execute(text(f'SET search_path TO "{schema}"'))
    Base.metadata.create_all(bind=connection)

    Session = sessionmaker(bind=connection)
    session = Session()
    return session, connection, schema


def test_parse_things_recurrence_rule():
    payload = {"fu": 16, "fa": 2, "of": {"dy": 1}, "sr": "2025-01-01"}
    plist_bytes = plistlib.dumps(payload)

    rule = ThingsRecurrenceParser.parse_recurrence_rule(plist_bytes)

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


def test_complete_repeating_task_is_idempotent(test_db_engine):
    session, connection, schema = _build_session(test_db_engine)
    try:
        task = Task(
            user_id="user",
            title="Repeat",
            status="today",
            recurrence_rule={"type": "daily", "interval": 1},
            repeating=True,
            repeat_template=True,
        )
        session.add(task)
        session.commit()
        session.refresh(task)

        first = RecurrenceService.complete_repeating_task(session, task)
        session.commit()
        assert first is not None

        second = RecurrenceService.complete_repeating_task(session, task)
        session.commit()
        assert second is not None
        assert first.id == second.id
    finally:
        session.close()
        connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        connection.close()
