"""Helpers for safe download response headers."""

from __future__ import annotations

import re
import unicodedata
from urllib.parse import quote

DEFAULT_MARKDOWN_DOWNLOAD_FILENAME = "download.md"
DEFAULT_TEXT_DOWNLOAD_FILENAME = "download.txt"


def _sanitize_header_filename(filename: str, *, default_filename: str) -> str:
    """Return a safe filename with header-breaking characters removed."""
    sanitized = filename.replace("\r", " ").replace("\n", " ")
    sanitized = re.sub(r"\s+", " ", sanitized).strip()
    return sanitized or default_filename


def _ascii_fallback_filename(filename: str, *, default_filename: str) -> str:
    """Return an ASCII fallback for legacy user agents."""
    normalized = unicodedata.normalize("NFKD", filename)
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii")
    ascii_only = re.sub(r"[^\x20-\x7E]", "", ascii_only).strip()
    return ascii_only or default_filename


def _escape_quoted_string(value: str) -> str:
    """Escape quoted-string characters for header values."""
    return value.replace("\\", "\\\\").replace('"', r"\"")


def _download_headers(filename: str, *, default_filename: str) -> dict[str, str]:
    """Build a Unicode-safe Content-Disposition header for file downloads."""
    safe_filename = _sanitize_header_filename(
        filename,
        default_filename=default_filename,
    )
    ascii_filename = _escape_quoted_string(
        _ascii_fallback_filename(safe_filename, default_filename=default_filename)
    )
    utf8_filename = quote(safe_filename.encode("utf-8"))
    disposition = (
        f'attachment; filename="{ascii_filename}"; ' f"filename*=UTF-8''{utf8_filename}"
    )
    return {"Content-Disposition": disposition}


def markdown_download_headers(filename: str) -> dict[str, str]:
    """Build a Unicode-safe Content-Disposition header for markdown downloads."""
    return _download_headers(
        filename,
        default_filename=DEFAULT_MARKDOWN_DOWNLOAD_FILENAME,
    )


def plain_text_download_headers(filename: str) -> dict[str, str]:
    """Build a Unicode-safe Content-Disposition header for plain-text downloads."""
    return _download_headers(
        filename,
        default_filename=DEFAULT_TEXT_DOWNLOAD_FILENAME,
    )
