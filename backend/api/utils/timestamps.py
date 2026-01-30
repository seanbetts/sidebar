"""Timestamp parsing helpers for offline sync."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from api.exceptions import BadRequestError


def parse_client_timestamp(value: Any, *, field_name: str) -> datetime | None:
    """Parse a client-provided timestamp into a timezone-aware datetime.

    Supports ISO-8601 strings, UNIX seconds, or UNIX milliseconds.

    Args:
        value: Input timestamp value.
        field_name: Field name for error messaging.

    Returns:
        Parsed datetime in UTC, or None if value is empty.

    Raises:
        BadRequestError: If the timestamp is invalid.
    """
    if value is None:
        return None

    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value

    if isinstance(value, int | float):
        timestamp = float(value)
        if timestamp > 10_000_000_000:
            timestamp = timestamp / 1000.0
        return datetime.fromtimestamp(timestamp, tz=UTC)

    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return None
        try:
            return parse_client_timestamp(float(raw), field_name=field_name)
        except ValueError:
            pass
        try:
            parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError as exc:
            raise BadRequestError(f"Invalid {field_name} timestamp") from exc
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=UTC)
        return parsed

    raise BadRequestError(f"Invalid {field_name} timestamp")
