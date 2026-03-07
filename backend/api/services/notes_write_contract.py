"""Shared contract helpers for canonical note content writes."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from api.exceptions import BadRequestError
from api.services.notes_document_types import (
    document_version,
    project_plain_text_from_document,
    validate_note_document,
)
from api.services.notes_title import derive_note_title_from_document

MAX_NOTE_PLAIN_TEXT_CHARS = 2_097_152


@dataclass(frozen=True)
class CanonicalNoteWrite:
    """Canonical note write payload."""

    document: dict[str, Any]
    document_version: int
    plain_text: str
    title: str


def validate_plain_text(plain_text: Any) -> str:
    """Validate projected plain-text note content."""
    if not isinstance(plain_text, str):
        raise BadRequestError("plain_text required")
    if len(plain_text) > MAX_NOTE_PLAIN_TEXT_CHARS:
        raise BadRequestError("plain_text exceeds max length")
    return plain_text


def parse_note_write_payload(payload: dict[str, Any]) -> dict[str, Any]:
    """Parse and validate the required semantic note write payload."""
    title = payload.get("title")
    if isinstance(title, str) and title.strip():
        raise BadRequestError("Note titles are derived from note content")

    document = payload.get("document")
    if document is None:
        raise BadRequestError("document required")
    return validate_note_document(document)


def build_canonical_note_write(
    document: Any,
) -> CanonicalNoteWrite:
    """Build canonical semantic and derived payloads for note writes."""
    validated_document = validate_note_document(document)
    resolved_plain_text = validate_plain_text(
        project_plain_text_from_document(validated_document)
    )
    resolved_title = derive_note_title_from_document(validated_document)
    return CanonicalNoteWrite(
        document=validated_document,
        document_version=document_version(validated_document),
        plain_text=resolved_plain_text,
        title=resolved_title,
    )
