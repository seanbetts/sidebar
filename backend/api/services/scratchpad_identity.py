"""Shared helpers for identifying and shaping scratchpad notes."""

from __future__ import annotations

from typing import Any

SCRATCHPAD_TITLE = "✏️ Scratchpad"
LEGACY_SCRATCHPAD_TITLE = f"# {SCRATCHPAD_TITLE}"


def scratchpad_titles() -> tuple[str, str]:
    """Return canonical and legacy scratchpad titles."""
    return (SCRATCHPAD_TITLE, LEGACY_SCRATCHPAD_TITLE)


def is_scratchpad_title(title: str | None) -> bool:
    """Return whether a title refers to the scratchpad note."""
    return isinstance(title, str) and title in scratchpad_titles()


def strip_scratchpad_heading(content: str) -> str:
    """Strip canonical or legacy scratchpad heading text from content."""
    if not content:
        return ""
    trimmed = content.lstrip()
    if trimmed.startswith(LEGACY_SCRATCHPAD_TITLE):
        lines = trimmed.splitlines()
        if not lines:
            return ""
        return "\n".join(lines[1:]).lstrip("\n").strip("\n")
    if trimmed.startswith(SCRATCHPAD_TITLE):
        lines = trimmed.splitlines()
        if not lines:
            return ""
        return "\n".join(lines[1:]).lstrip("\n").strip("\n")
    return content.strip("\n")


def _title_only_blocks() -> list[dict[str, object]]:
    return [
        {
            "type": "title",
            "content": [{"text": SCRATCHPAD_TITLE, "marks": []}],
        }
    ]


def scratchpad_document(content: str) -> dict[str, Any]:
    """Build the canonical semantic scratchpad document from note content."""
    body_plain_text = strip_scratchpad_heading(content).strip()
    if not body_plain_text:
        return {"version": 1, "blocks": _title_only_blocks()}

    body_blocks = [
        {
            "type": "paragraph",
            "content": [{"text": line, "marks": []}],
        }
        for line in body_plain_text.split("\n")
    ]
    return {
        "version": 1,
        "blocks": [*_title_only_blocks(), *body_blocks],
    }
