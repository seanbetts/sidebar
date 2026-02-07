"""Shared URL normalization helpers for website and YouTube flows."""

from __future__ import annotations

import re
from urllib.parse import ParseResult, parse_qs, urlparse

YOUTUBE_DOMAINS = ("youtube.com", "youtu.be")
YOUTUBE_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{6,}$")


def _parse_url_candidate(raw: str) -> tuple[str, ParseResult]:
    cleaned = (raw or "").strip()
    if not cleaned:
        raise ValueError("Invalid URL")
    candidate = (
        cleaned if cleaned.startswith(("http://", "https://")) else f"https://{cleaned}"
    )
    parsed = urlparse(candidate)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("Invalid URL")
    if not parsed.netloc:
        raise ValueError("Invalid URL")
    return cleaned, parsed


def _normalize_host(host: str | None) -> str:
    return (host or "").strip().lower().rstrip(".")


def is_youtube_host(host: str) -> bool:
    """Return whether a hostname belongs to YouTube or youtu.be."""
    normalized = _normalize_host(host)
    return (
        normalized == "youtube.com"
        or normalized.endswith(".youtube.com")
        or normalized == "youtu.be"
        or normalized.endswith(".youtu.be")
    )


def _valid_youtube_id(candidate: str) -> str | None:
    value = candidate.strip()
    if not value:
        return None
    if not YOUTUBE_ID_PATTERN.match(value):
        return None
    return value


def extract_youtube_video_id(raw: str) -> str | None:
    """Extract a YouTube video ID from supported URL formats."""
    try:
        _cleaned, parsed = _parse_url_candidate(raw)
    except ValueError:
        return None

    host = _normalize_host(parsed.hostname)
    if not is_youtube_host(host):
        return None

    if host == "youtu.be" or host.endswith(".youtu.be"):
        parts = [part for part in parsed.path.split("/") if part]
        if not parts:
            return None
        return _valid_youtube_id(parts[0])

    query = parse_qs(parsed.query)
    if query.get("v"):
        return _valid_youtube_id(query["v"][0])

    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) >= 2 and parts[0] in {"shorts", "embed", "live", "v"}:
        return _valid_youtube_id(parts[1])

    return None


def normalize_youtube_url(raw: str) -> str:
    """Normalize supported YouTube URL forms to canonical watch URL."""
    video_id = extract_youtube_video_id(raw)
    if not video_id:
        raise ValueError("Invalid YouTube URL")
    return f"https://www.youtube.com/watch?v={video_id}"


def normalize_website_url(raw: str) -> str:
    """Normalize a website URL for storage and dedupe checks."""
    cleaned, parsed = _parse_url_candidate(raw)
    host = _normalize_host(parsed.hostname)

    if is_youtube_host(host):
        return normalize_youtube_url(cleaned)

    normalized = parsed._replace(query="", fragment="")
    return normalized.geturl()
