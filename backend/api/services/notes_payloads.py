"""Shared notes payload parsing helpers."""

from __future__ import annotations

from typing import Any

from api.exceptions import BadRequestError


def read_plain_text_field(payload: dict[str, Any]) -> str | None:
    """Return plain_text from snake_case/camelCase payload keys."""
    plain_text = payload.get("plain_text")
    if plain_text is None:
        plain_text = payload.get("plainText")
    if plain_text is None:
        return None
    return str(plain_text)


def parse_content_write_payload(payload: dict[str, Any]) -> tuple[str, str]:
    """Parse required content and plain-text cache fields."""
    content = payload.get("content")
    if content is None:
        raise BadRequestError("content required")
    plain_text = read_plain_text_field(payload)
    if plain_text is None:
        raise BadRequestError("plain_text required")
    return str(content), plain_text
