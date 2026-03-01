"""Canonical notes content codec helpers."""

from __future__ import annotations

import base64
from dataclasses import dataclass
from typing import Any

from api.exceptions import BadRequestError

MAX_NOTE_PLAIN_TEXT_CHARS = 2_097_152
DEFAULT_RTF_FONT_NAME = "Helvetica"
DEFAULT_RTF_FONT_SIZE_HALF_POINTS = 24


@dataclass(frozen=True)
class CanonicalNoteContent:
    """Canonical note payload generated from plain text."""

    content: str
    plain_text: str


def validate_plain_text(plain_text: Any) -> str:
    """Validate plain-text input for note writes."""
    if not isinstance(plain_text, str):
        raise BadRequestError("plain_text required")
    if len(plain_text) > MAX_NOTE_PLAIN_TEXT_CHARS:
        raise BadRequestError("plain_text exceeds max length")
    return plain_text


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
        f"{{\\fonttbl{{\\f0\\fnil\\fcharset0 {DEFAULT_RTF_FONT_NAME};}}}}"
        f"\\f0\\fs{DEFAULT_RTF_FONT_SIZE_HALF_POINTS} "
    )
    return f"{prefix}{body}}}".encode()


def plain_text_to_rtf_base64(plain_text: str) -> str:
    """Encode validated plain text into canonical Base64 RTF."""
    validated = validate_plain_text(plain_text)
    rtf_bytes = plain_text_to_rtf_bytes(validated)
    return base64.b64encode(rtf_bytes).decode("ascii")


def canonical_note_content_from_plain_text(plain_text: Any) -> CanonicalNoteContent:
    """Return canonical content/plain-text pair from plain-text input."""
    validated = validate_plain_text(plain_text)
    return CanonicalNoteContent(
        content=plain_text_to_rtf_base64(validated),
        plain_text=validated,
    )


def note_plain_text_from_record(
    content: str | None,
    metadata: dict[str, Any] | None,
) -> str:
    """Resolve note plain text from canonical metadata."""
    _ = content  # Content remains encoded RTF Base64 and is not a plain-text fallback.
    plain_text = (metadata or {}).get("plain_text")
    if isinstance(plain_text, str):
        return plain_text
    return ""
