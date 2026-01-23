"""Parser for recurrence rules stored in plist format."""

from __future__ import annotations

import plistlib
from datetime import UTC, date, datetime
from typing import Any


class RecurrencePlistParser:
    """Parse recurrence rules from plist bytes."""

    TYPE_MAP = {16: "daily", 256: "weekly", 8: "monthly"}

    @staticmethod
    def parse_recurrence_rule(plist_data: bytes | None) -> dict[str, Any] | None:
        """Parse binary plist recurrence data.

        Args:
            plist_data: Raw bytes from recurrence fields.

        Returns:
            Parsed recurrence rule dict or None if not repeating.
        """
        if not plist_data:
            return None
        try:
            payload = plistlib.loads(plist_data)
        except Exception:
            return None

        rule_type = RecurrencePlistParser.TYPE_MAP.get(payload.get("fu"))
        if not rule_type:
            return None

        interval = max(1, int(payload.get("fa") or 1))
        occurrence = payload.get("of") or {}
        if isinstance(occurrence, list):
            occurrence = occurrence[0] if occurrence else {}
        start_date = RecurrencePlistParser._parse_date(payload.get("sr"))
        end_date = RecurrencePlistParser._parse_date(payload.get("ed"))

        rule: dict[str, Any] = {
            "type": rule_type,
            "interval": interval,
            "start_date": start_date.isoformat() if start_date else None,
            "end_date": end_date.isoformat() if end_date else None,
        }

        if rule_type == "weekly":
            weekday = occurrence.get("wd")
            if weekday is not None:
                rule["weekday"] = int(weekday)
        if rule_type == "monthly":
            day_of_month = occurrence.get("dy")
            if day_of_month is not None:
                rule["day_of_month"] = int(day_of_month)

        return rule

    @staticmethod
    def _parse_date(value: Any) -> date | None:
        if not value:
            return None
        if isinstance(value, int | float):
            try:
                return datetime.fromtimestamp(float(value), tz=UTC).date()
            except (OSError, ValueError):
                return None
        if isinstance(value, date) and not isinstance(value, datetime):
            return value
        if isinstance(value, datetime):
            return value.date()
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None
        return parsed.date()
