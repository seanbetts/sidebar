"""Shared utility helpers for web-save parser."""

from __future__ import annotations

import re
from datetime import datetime

CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")


def ensure_url(value: str) -> str:
    """Ensure URL has a scheme."""
    if value.startswith(("http://", "https://")):
        return value
    return f"https://{value}"


def strip_control_chars(value: str) -> str:
    """Replace non-XML control characters that break lxml/readability."""
    if not value:
        return value
    return CONTROL_CHARS_RE.sub(" ", value)


def clean_metadata_value(value: str | None) -> str | None:
    """Normalize parser metadata fields and drop placeholder sentinel values."""
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    if cleaned.lower() in {"undefined", "null", "none", "n/a"}:
        return None
    return cleaned


def parse_datetime(value: str | None) -> datetime | None:
    """Parse ISO-like datetime strings."""
    if not value:
        return None
    cleaned = value.strip()
    try:
        return datetime.fromisoformat(cleaned.replace("Z", "+00:00"))
    except ValueError:
        return None
