"""Helpers for deriving note titles from note content."""

from __future__ import annotations

from typing import Any

from api.services.notes_document_types import validate_note_document

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
    """Return a note title derived from block 0 title semantics."""
    validated_document = validate_note_document(document)
    blocks = validated_document.get("blocks", [])
    if not blocks:
        return DEFAULT_NOTE_TITLE

    first_block = blocks[0]
    if first_block.get("type") != "title":
        return DEFAULT_NOTE_TITLE

    content = first_block.get("content")
    if not isinstance(content, list):
        return DEFAULT_NOTE_TITLE

    projected = "".join(_project_title_segment(segment) for segment in content).strip()
    if not projected:
        return DEFAULT_NOTE_TITLE
    return projected[:MAX_NOTE_TITLE_LENGTH]


def _project_title_segment(segment: Any) -> str:
    """Project one title inline segment into title text."""
    if not isinstance(segment, dict):
        return ""
    text = segment.get("text")
    if isinstance(text, str) and text:
        return text
    link = segment.get("link")
    if isinstance(link, dict):
        link_url = link.get("url")
        if isinstance(link_url, str):
            return link_url
    return ""
