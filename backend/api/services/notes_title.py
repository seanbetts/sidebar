"""Helpers for deriving note titles from note content."""

from __future__ import annotations

import re

DEFAULT_NOTE_TITLE = "New Note"
MAX_NOTE_TITLE_LENGTH = 120
MARKDOWN_HEADING_PREFIX = re.compile(r"^#{1,6}\s+")


def derive_note_title(plain_text: str | None) -> str:
    """Return a note title derived from the first non-empty content line."""
    if not isinstance(plain_text, str):
        return DEFAULT_NOTE_TITLE

    for line in plain_text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        normalized = MARKDOWN_HEADING_PREFIX.sub("", stripped, count=1).strip()
        if normalized:
            return normalized[:MAX_NOTE_TITLE_LENGTH]
    return DEFAULT_NOTE_TITLE
