"""Helpers for deriving note titles from note content."""

from __future__ import annotations

from typing import Any

from api.services.notes_document_types import project_plain_text_from_document

DEFAULT_NOTE_TITLE = "New Note"
MAX_NOTE_TITLE_LENGTH = 120


def derive_note_title(plain_text: str | None) -> str:
    """Return a note title derived from the first non-empty content line."""
    if not isinstance(plain_text, str):
        return DEFAULT_NOTE_TITLE

    for line in plain_text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        return stripped[:MAX_NOTE_TITLE_LENGTH]
    return DEFAULT_NOTE_TITLE


def derive_note_title_from_document(document: dict[str, Any]) -> str:
    """Return a note title derived from the semantic note document."""
    return derive_note_title(project_plain_text_from_document(document))
