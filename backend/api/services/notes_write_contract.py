"""Shared contract helpers for canonical note content writes."""

from __future__ import annotations

import base64
import binascii
import logging
import os
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
NOTES_READ_DIAGNOSTICS_ENV_VAR = "NOTES_READ_CANONICALITY_DIAGNOSTICS"
_SEEN_READ_DIAGNOSTIC_KEYS: set[tuple[str, str]] = set()
logger = logging.getLogger(__name__)


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


def canonical_metadata_issues(metadata: Any) -> list[str]:
    """Return canonical metadata issues for diagnostics."""
    if not isinstance(metadata, dict):
        return ["metadata is not a dict"]
    issues: list[str] = []
    if metadata.get("content_format") != "rtf":
        issues.append("metadata.content_format != rtf")
    plain_text = metadata.get("plain_text")
    if not isinstance(plain_text, str):
        issues.append("metadata.plain_text missing or not string")
    return issues


def _read_diagnostics_enabled() -> bool:
    override = (os.getenv(NOTES_READ_DIAGNOSTICS_ENV_VAR) or "").strip().lower()
    if override in {"1", "true", "yes", "on"}:
        return True
    if override in {"0", "false", "no", "off"}:
        return False
    app_env = (os.getenv("APP_ENV") or "").strip().lower()
    return bool(os.getenv("TESTING")) or app_env in {"local", "dev", "test"}


def reset_read_diagnostic_cache_for_tests() -> None:
    """Reset one-shot read diagnostics cache.

    Intended for deterministic test assertions.
    """
    _SEEN_READ_DIAGNOSTIC_KEYS.clear()


def diagnose_note_read_canonicality(
    *,
    note_id: Any,
    user_id: Any,
    context: str,
    content: Any | None,
    metadata: Any,
    require_content: bool = True,
) -> list[str]:
    """Emit non-fatal diagnostics when a read path encounters non-canonical notes."""
    issues = canonical_metadata_issues(metadata)
    if require_content:
        issues.extend(canonical_content_issues(content))
    if not issues or not _read_diagnostics_enabled():
        return issues
    key = (str(note_id), context)
    if key in _SEEN_READ_DIAGNOSTIC_KEYS:
        return issues
    _SEEN_READ_DIAGNOSTIC_KEYS.add(key)
    logger.warning(
        "Non-canonical note observed on read: note_id=%s "
        "user_id=%s context=%s issues=%s",
        note_id,
        user_id,
        context,
        "; ".join(issues),
    )
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


def apply_canonical_note_metadata(
    metadata: dict[str, Any] | None, plain_text: str
) -> dict[str, Any]:
    """Return metadata with canonical note fields set by the server."""
    next_metadata = dict(metadata or {})
    next_metadata["content_format"] = "rtf"
    next_metadata["plain_text"] = plain_text
    return next_metadata
