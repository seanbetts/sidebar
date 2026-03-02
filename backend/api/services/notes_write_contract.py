"""Shared contract helpers for canonical note content writes."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from typing import Any

from api.exceptions import BadRequestError
from api.services.notes_content_codec import (
    plain_text_to_rtf_base64 as encode_plain_text_to_rtf_base64,
)
from api.services.notes_content_codec import (
    validate_plain_text,
)

MAX_NOTE_RTF_BYTES = 2_097_152
JSON_HEADROOM = 512
MAX_NOTE_CONTENT_B64_CHARS = ((MAX_NOTE_RTF_BYTES + 2) // 3) * 4 + JSON_HEADROOM


@dataclass(frozen=True)
class CanonicalNoteWrite:
    """Canonical note write payload."""

    content: str
    plain_text: str


def plain_text_to_rtf_base64(plain_text: str) -> str:
    """Encode plain text into canonical Base64 RTF."""
    return encode_plain_text_to_rtf_base64(plain_text)


def is_canonical_base64_rtf(content: Any) -> bool:
    """Return True when content is canonical Base64 RTF and within limits."""
    if not isinstance(content, str):
        return False
    if len(content) > MAX_NOTE_CONTENT_B64_CHARS:
        return False
    try:
        decoded = base64.b64decode(content, validate=True)
    except (ValueError, binascii.Error):
        return False
    if len(decoded) > MAX_NOTE_RTF_BYTES:
        return False
    return decoded.startswith(b"{\\rtf")


def canonical_content_issues(content: Any) -> list[str]:
    """Return canonical content issues for diagnostics."""
    issues: list[str] = []
    if not isinstance(content, str):
        return ["content is not a string"]
    if len(content) > MAX_NOTE_CONTENT_B64_CHARS:
        issues.append("content exceeds max encoded length")
        return issues
    try:
        decoded = base64.b64decode(content, validate=True)
    except (ValueError, binascii.Error):
        return ["content is not valid Base64"]
    if len(decoded) > MAX_NOTE_RTF_BYTES:
        issues.append("decoded content exceeds max size")
    if not decoded.startswith(b"{\\rtf"):
        issues.append("decoded content does not start with {\\rtf")
    return issues


def validate_canonical_base64_rtf(content: Any) -> str:
    """Validate canonical content and return the normalized content string."""
    if not isinstance(content, str):
        raise BadRequestError("content required")
    if len(content) > MAX_NOTE_CONTENT_B64_CHARS:
        raise BadRequestError("content exceeds max encoded length")
    try:
        decoded = base64.b64decode(content, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise BadRequestError("content must be valid Base64") from exc
    if len(decoded) > MAX_NOTE_RTF_BYTES:
        raise BadRequestError("content exceeds max decoded size")
    if not decoded.startswith(b"{\\rtf"):
        raise BadRequestError("content must decode to RTF bytes")
    return content


def build_canonical_note_write(
    content: Any,
    plain_text: Any,
) -> CanonicalNoteWrite:
    """Build canonical content/plain-text payload for note writes."""
    canonical_content = validate_canonical_base64_rtf(content)
    resolved_plain_text = validate_plain_text(plain_text)
    return CanonicalNoteWrite(
        content=canonical_content,
        plain_text=resolved_plain_text,
    )
