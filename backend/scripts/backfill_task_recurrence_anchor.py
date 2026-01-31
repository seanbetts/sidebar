#!/usr/bin/env python3
"""Backfill recurrence anchor_date + next_instance_date for repeating tasks."""

from __future__ import annotations

import argparse
import logging
from datetime import date
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
import sys

sys.path.insert(0, str(BACKEND_ROOT))

from sqlalchemy import or_

from api.db.session import SessionLocal, set_session_user_id
from api.models.task import Task
from api.services.recurrence_service import RecurrenceService

logger = logging.getLogger(__name__)


def _parse_anchor(rule: dict | None) -> date | None:
    return RecurrenceService._parse_anchor_date(rule)


def backfill(user_id: str | None, *, limit: int | None, dry_run: bool) -> None:
    db = SessionLocal()
    processed = 0
    updated = 0
    try:
        query = db.query(Task).filter(
            Task.deleted_at.is_(None),
            Task.repeating.is_(True),
            Task.recurrence_rule.is_not(None),
        )
        if user_id:
            set_session_user_id(db, user_id)
            query = query.filter(Task.user_id == user_id)
        query = query.filter(
            or_(
                Task.next_instance_date.is_(None),
                Task.recurrence_rule["anchor_date"].astext.is_(None),
                Task.recurrence_rule["anchor_date"].astext == "",
            )
        )
        if limit:
            query = query.limit(limit)

        tasks = query.all()
        for task in tasks:
            processed += 1
            rule = dict(task.recurrence_rule or {})
            anchor = _parse_anchor(rule)
            if anchor is None:
                if task.deadline:
                    anchor = task.deadline
                else:
                    continue
                rule["anchor_date"] = anchor.isoformat()

            next_date = task.next_instance_date
            if next_date is None:
                next_date = RecurrenceService.calculate_next_occurrence(
                    rule, anchor
                )

            if dry_run:
                updated += 1
                continue

            task.recurrence_rule = rule
            db.flush()
            from sqlalchemy.orm.attributes import flag_modified
            flag_modified(task, "recurrence_rule")
            task.next_instance_date = next_date
            updated += 1

        if not dry_run:
            db.commit()
        logger.info(
            "recurrence anchor backfill processed=%s updated=%s",
            processed,
            updated,
        )
    finally:
        db.close()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Backfill task recurrence anchors")
    parser.add_argument("--user-id", help="Optional user ID to scope backfill")
    parser.add_argument("--limit", type=int, help="Limit number of tasks")
    parser.add_argument("--dry-run", action="store_true", help="No writes")
    args = parser.parse_args()

    backfill(args.user_id, limit=args.limit, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
