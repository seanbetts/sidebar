"""Helpers for chat title generation."""

from __future__ import annotations

import hashlib

from api.constants import ChatConstants


def build_title_cache_key(user_msg: str, assistant_msg: str) -> str:
    """Build a stable cache key from the title source messages."""
    combined = f"{user_msg}\n{assistant_msg}"
    return hashlib.sha256(combined.encode("utf-8")).hexdigest()


def sanitize_title(raw_title: str) -> str:
    """Normalize a generated chat title into the persisted title contract."""
    title = (raw_title or "").strip()
    if not title:
        raise ValueError("Empty title returned")
    if title.lower().startswith("title:"):
        title = title.split(":", 1)[1].strip()
    title = title.strip("\"'").strip()
    if "\n" in title:
        title = title.splitlines()[0].strip()
    title = " ".join(title.split())

    words = title.split()
    if len(words) > ChatConstants.TITLE_MAX_WORDS:
        title = " ".join(words[: ChatConstants.TITLE_MAX_WORDS])

    if not title:
        raise ValueError("Invalid title after sanitization")
    if len(title) > 100:
        title = title[:100].rstrip()
    return title
