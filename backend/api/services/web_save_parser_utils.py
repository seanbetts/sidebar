"""Shared utility helpers for web-save parser."""

from __future__ import annotations

import re

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
