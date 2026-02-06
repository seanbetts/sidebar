"""Reading-time helpers for website content."""

from __future__ import annotations

import re

from api.services.web_save_tagger import (
    calculate_reading_time,
    compute_word_count,
    count_images,
)

_FRONTMATTER_PREFIX = "---"
_MIN_PATTERN = re.compile(r"^(\d+)\s*mins?$", re.IGNORECASE)
_HR_PATTERN = re.compile(r"^(\d+)\s*hrs?\s*(?:(\d+)\s*mins?)?$", re.IGNORECASE)


def normalize_reading_time(value: str) -> str:
    """Normalize reading time to a consistent display format."""
    trimmed = value.strip().strip("'\"")
    if not trimmed:
        return ""

    hour_match = _HR_PATTERN.match(trimmed)
    if hour_match:
        hours = int(hour_match.group(1))
        mins = int(hour_match.group(2)) if hour_match.group(2) else 0
        total_minutes = hours * 60 + mins
    else:
        minute_match = _MIN_PATTERN.match(trimmed)
        if not minute_match:
            return trimmed
        total_minutes = int(minute_match.group(1))

    if total_minutes >= 60:
        hours = total_minutes // 60
        remaining = total_minutes % 60
        hour_label = "hr" if hours == 1 else "hrs"
        if remaining == 0:
            return f"{hours} {hour_label}"
        minute_label = "min" if remaining == 1 else "mins"
        return f"{hours} {hour_label} {remaining} {minute_label}"

    minute_label = "min" if total_minutes == 1 else "mins"
    return f"{total_minutes} {minute_label}"


def extract_reading_time_from_frontmatter(content: str | None) -> str | None:
    """Extract reading time from markdown frontmatter when present."""
    if not content or not content.startswith(_FRONTMATTER_PREFIX):
        return None
    end = content.find("\n---", 3)
    if end == -1:
        return None

    frontmatter = content[4:end]
    for line in frontmatter.split("\n"):
        if not line.startswith("reading_time:"):
            continue
        value = line[13:].strip()
        if not value:
            return None
        normalized = normalize_reading_time(value)
        return normalized or None
    return None


def derive_reading_time(content: str | None) -> str | None:
    """Derive a reading-time string from content/frontmatter."""
    if not content:
        return None

    from_frontmatter = extract_reading_time_from_frontmatter(content)
    if from_frontmatter:
        return from_frontmatter

    word_count = compute_word_count(content)
    image_count = count_images(content)
    if word_count <= 0 and image_count <= 0:
        return None
    return calculate_reading_time(word_count, image_count=image_count)
