"""Shared contract helpers for canonical note content writes."""

from __future__ import annotations

import base64
import binascii
import os
from dataclasses import dataclass
from typing import Any

from api.exceptions import BadRequestError

MAX_NOTE_RTF_BYTES = 2_097_152
JSON_HEADROOM = 512
MAX_NOTE_CONTENT_B64_CHARS = ((MAX_NOTE_RTF_BYTES + 2) // 3) * 4 + JSON_HEADROOM
MAX_NOTE_PLAIN_TEXT_CHARS = 2_097_152
STRICT_NOTES_WRITE_ENV_VAR = "NOTES_STRICT_RTF_WRITES"


@dataclass(frozen=True)
class CanonicalNoteWrite:
    """Canonical note write payload."""

    content: str
    plain_text: str


def strict_content_writes_enabled() -> bool:
    """Return whether strict canonical writes are required."""
    value = (os.getenv(STRICT_NOTES_WRITE_ENV_VAR) or "").strip().lower()
    return value in {"1", "true", "yes", "on"}


def _rtf_escape_text(text: str) -> str:
    output: list[str] = []
    for char in text:
        if char == "\\":
            output.append("\\\\")
        elif char == "{":
            output.append("\\{")
        elif char == "}":
            output.append("\\}")
        elif char == "\t":
            output.append("\\tab ")
        else:
            codepoint = ord(char)
            if 0x20 <= codepoint <= 0x7E:
                output.append(char)
                continue
            signed = codepoint if codepoint <= 32767 else codepoint - 65536
            output.append(f"\\u{signed}?")
    return "".join(output)


def plain_text_to_rtf_bytes(plain_text: str) -> bytes:
    """Encode plain text into deterministic UTF-8 RTF bytes."""
    normalized = plain_text.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    escaped_lines = [_rtf_escape_text(line) for line in lines]
    body = "\\par\n".join(escaped_lines)
    prefix = (
        "{\\rtf1\\ansi\\deff0"
        "{\\fonttbl{\\f0\\fnil\\fcharset0 Helvetica;}}"
        "\\f0\\fs24 "
    )
    return f"{prefix}{body}}}".encode()


def plain_text_to_rtf_base64(plain_text: str) -> str:
    """Encode plain text into canonical Base64 RTF."""
    rtf_bytes = plain_text_to_rtf_bytes(plain_text)
    return base64.b64encode(rtf_bytes).decode("ascii")


def _validate_plain_text(plain_text: Any) -> str:
    if not isinstance(plain_text, str):
        raise BadRequestError("plain_text required")
    if len(plain_text) > MAX_NOTE_PLAIN_TEXT_CHARS:
        raise BadRequestError("plain_text exceeds max length")
    return plain_text


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
    *,
    existing_plain_text: str | None = None,
) -> CanonicalNoteWrite:
    """Build canonical content/plain-text payload for note writes.

    Strict mode:
        Requires canonical Base64 RTF `content` and explicit `plain_text`.

    Compatibility mode:
        Accepts legacy plain-text `content` and canonicalizes it to Base64 RTF.
        If `content` is already canonical and `plain_text` is omitted, falls back
        to existing note metadata plain text when available.
    """
    strict_mode = strict_content_writes_enabled()
    if strict_mode:
        canonical_content = validate_canonical_base64_rtf(content)
        resolved_plain_text = _validate_plain_text(plain_text)
        return CanonicalNoteWrite(
            content=canonical_content,
            plain_text=resolved_plain_text,
        )

    if not isinstance(content, str):
        raise BadRequestError("content required")

    if is_canonical_base64_rtf(content):
        if plain_text is None:
            if existing_plain_text is None:
                raise BadRequestError("plain_text required")
            resolved_plain_text = _validate_plain_text(existing_plain_text)
        else:
            resolved_plain_text = _validate_plain_text(plain_text)
        return CanonicalNoteWrite(content=content, plain_text=resolved_plain_text)

    if plain_text is None:
        resolved_plain_text = _validate_plain_text(content)
    else:
        resolved_plain_text = _validate_plain_text(plain_text)
    canonical_content = plain_text_to_rtf_base64(resolved_plain_text)
    validate_canonical_base64_rtf(canonical_content)
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
